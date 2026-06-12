import Foundation
import MCPClient

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if os(macOS) || os(Linux)

/// Stdio transport that spawns a subprocess and drains stderr so logging cannot deadlock pipes.
///
/// Reads run on a dedicated background task so `send` and `receive` never block each other.
final class SubprocessStdioTransport: MCPTransport, @unchecked Sendable {
    private let command: String
    private let arguments: [String]
    private let environment: [String: String]
    private let logStderr: Bool

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutReaderTask: Task<Void, Never>?
    private var stderrDrainTask: Task<Void, Never>?
    private var isConnected = false

    private let lineBuffer = LineBuffer()
    private let log = MCPCLogging.logger("transport.stdio")

    init(
        command: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        logStderr: Bool = false
    ) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.logStderr = logStderr
    }

    func connect() async throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: command)
        proc.arguments = arguments
        proc.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        do {
            try proc.run()
        } catch {
            log.error(
                "Failed to spawn subprocess",
                metadata: [
                    "command": .string(command),
                    "error": .string(error.localizedDescription),
                ]
            )
            throw MCPError.processSpawnFailed(reason: error.localizedDescription)
        }

        log.info(
            "Spawned subprocess",
            metadata: [
                "command": .string(command),
                "pid": .stringConvertible(proc.processIdentifier),
                "args": .string(arguments.joined(separator: " ")),
            ]
        )

        process = proc
        stdinPipe = stdin
        isConnected = true

        let stdoutHandle = stdout.fileHandleForReading
        let buffer = lineBuffer
        stdoutReaderTask = Task.detached { [weak self] in
            await self?.readStdoutLoop(handle: stdoutHandle, process: proc, buffer: buffer)
        }

        let stderrHandle = stderr.fileHandleForReading
        let shouldLogStderr = logStderr
        let processID = proc.processIdentifier
        stderrDrainTask = Task.detached {
            while !Task.isCancelled {
                let chunk = stderrHandle.availableData
                if chunk.isEmpty {
                    var status: Int32 = 0
                    let exited = waitpid(processID, &status, WNOHANG) > 0
                    if exited {
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(10))
                    continue
                }
                if shouldLogStderr, let text = String(data: chunk, encoding: .utf8), !text.isEmpty {
                    FileHandle.standardError.write(Data(text.utf8))
                }
            }
        }
    }

    func disconnect() async throws {
        guard isConnected || process != nil else { return }
        isConnected = false
        log.debug("Disconnecting stdio transport")

        stdinPipe?.fileHandleForWriting.closeFile()

        stdoutReaderTask?.cancel()
        stderrDrainTask?.cancel()
        if let stdoutReaderTask {
            _ = await stdoutReaderTask.value
        }
        stdoutReaderTask = nil
        stderrDrainTask = nil

        if let proc = process, proc.isRunning {
            try await Task.sleep(for: .milliseconds(100))
        }

        if let proc = process, proc.isRunning {
            proc.terminate()
            try await Task.sleep(for: .milliseconds(100))
        }

        #if os(macOS)
        if let proc = process, proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
        }
        #endif

        process = nil
        stdinPipe = nil

        await lineBuffer.cancelWaiters()
        log.debug("Stdio transport disconnected")
    }

    func send(_ data: Data) async throws {
        guard isConnected, let pipe = stdinPipe, let proc = process else {
            throw MCPError.connectionFailed(reason: "SubprocessStdioTransport is not connected")
        }

        guard proc.isRunning else {
            isConnected = false
            throw MCPError.transportClosed
        }

        var messageData = data
        messageData.append(0x0A)
        try pipe.fileHandleForWriting.write(contentsOf: messageData)
        log.trace("Sent message", metadata: ["bytes": .stringConvertible(messageData.count)])
    }

    func receive() async throws -> Data {
        let data = try await lineBuffer.dequeueOrWait(isConnected: isConnected)
        log.trace("Received message", metadata: ["bytes": .stringConvertible(data.count)])
        return data
    }

    private func readStdoutLoop(handle: FileHandle, process: Process, buffer: LineBuffer) async {
        var readBuffer = ""

        while !Task.isCancelled, isConnected {
            let chunk = handle.availableData

            if chunk.isEmpty {
                if !process.isRunning {
                    await failPendingReceivers()
                    return
                }
                try? await Task.sleep(for: .milliseconds(10))
                continue
            }

            guard let text = String(data: chunk, encoding: .utf8) else {
                continue
            }

            readBuffer.append(text)
            let lines = readBuffer.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count <= 1 {
                continue
            }

            readBuffer = String(lines[lines.count - 1])
            for index in 0..<(lines.count - 1) {
                let line = String(lines[index])
                guard !line.isEmpty, let data = line.data(using: .utf8) else {
                    continue
                }
                if let receiver = await buffer.enqueue(data) {
                    receiver.resume(returning: data)
                }
            }
        }
    }

    private func failPendingReceivers() async {
        isConnected = false
        let receivers = await lineBuffer.failAll()
        for receiver in receivers {
            receiver.resume(throwing: MCPError.transportClosed)
        }
    }
}

#endif
