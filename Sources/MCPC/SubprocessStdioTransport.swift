import Foundation
import MCPClient

#if os(macOS) || os(Linux)

/// Stdio transport that spawns a subprocess and drains stderr so logging cannot deadlock pipes.
actor SubprocessStdioTransport: MCPTransport {
    private let command: String
    private let arguments: [String]
    private let environment: [String: String]
    private let logStderr: Bool

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stderrDrainTask: Task<Void, Never>?
    private var bufferedLines: [String] = []
    private var readBuffer = ""
    private var isConnected = false

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
        guard !isConnected else { return }

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
            throw MCPError.processSpawnFailed(reason: error.localizedDescription)
        }

        process = proc
        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr
        isConnected = true

        let stderrHandle = stderr.fileHandleForReading
        let shouldLogStderr = logStderr
        stderrDrainTask = Task.detached {
            while !Task.isCancelled {
                let chunk = stderrHandle.availableData
                if chunk.isEmpty {
                    break
                }
                if shouldLogStderr, let text = String(data: chunk, encoding: .utf8), !text.isEmpty {
                    FileHandle.standardError.write(Data(text.utf8))
                }
            }
        }
    }

    func disconnect() async throws {
        guard let proc = process else { return }

        isConnected = false
        stderrDrainTask?.cancel()
        stderrDrainTask = nil

        stdinPipe?.fileHandleForWriting.closeFile()

        if proc.isRunning {
            try await Task.sleep(for: .milliseconds(100))
        }

        if proc.isRunning {
            proc.terminate()
            try await Task.sleep(for: .milliseconds(100))
        }

        #if os(macOS)
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
        }
        #endif

        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        bufferedLines = []
        readBuffer = ""
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
        pipe.fileHandleForWriting.write(messageData)
    }

    func receive() async throws -> Data {
        guard isConnected, let pipe = stdoutPipe else {
            throw MCPError.connectionFailed(reason: "SubprocessStdioTransport is not connected")
        }

        if !bufferedLines.isEmpty {
            let line = bufferedLines.removeFirst()
            guard let data = line.data(using: .utf8) else {
                throw MCPError.invalidResponse
            }
            return data
        }

        let handle = pipe.fileHandleForReading
        while !Task.isCancelled {
            let chunk = handle.availableData

            if chunk.isEmpty {
                isConnected = false
                throw MCPError.transportClosed
            }

            guard let text = String(data: chunk, encoding: .utf8) else {
                continue
            }

            readBuffer.append(text)

            let lines = readBuffer.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > 1 {
                for index in 0..<(lines.count - 1) {
                    let line = String(lines[index])
                    if !line.isEmpty {
                        bufferedLines.append(line)
                    }
                }
                readBuffer = String(lines[lines.count - 1])

                if !bufferedLines.isEmpty {
                    let firstLine = bufferedLines.removeFirst()
                    guard let data = firstLine.data(using: .utf8) else {
                        throw MCPError.invalidResponse
                    }
                    return data
                }
            }
        }

        throw MCPError.transportClosed
    }
}

#endif
