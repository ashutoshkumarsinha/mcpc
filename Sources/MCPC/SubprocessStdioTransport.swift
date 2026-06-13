import Foundation // Process, Pipe, FileHandle, Task
import MCPClient // MCPTransport protocol and MCP errors

#if canImport(Darwin) // macOS/iOS C APIs (waitpid, kill, SIGKILL)
import Darwin
#elseif canImport(Glibc) // Linux C APIs
import Glibc
#endif

#if os(macOS) || os(Linux) // Stdio subprocess transport only on desktop OSes

/// Stdio transport that spawns a subprocess and drains stderr so logging cannot deadlock pipes.
///
/// Reads run on a dedicated background task so `send` and `receive` never block each other.
final class SubprocessStdioTransport: MCPTransport, @unchecked Sendable { // `final` = no subclasses; manual Sendable because of Process/Pipe
    private let command: String // Executable path to spawn
    private let arguments: [String] // CLI arguments for the child process
    private let environment: [String: String] // Environment variables for the child
    private let workingDirectory: String? // Optional current working directory
    private let logStderr: Bool // Whether to copy child stderr to our stderr

    private var process: Process? // Running child process handle
    private var stdinPipe: Pipe? // Pipe connected to child stdin
    private var stdoutReaderTask: Task<Void, Never>? // Background task reading stdout lines
    private var stderrDrainTask: Task<Void, Never>? // Background task draining stderr
    private var isConnected = false // True after successful connect()

    private let lineBuffer = LineBuffer() // Async queue bridging stdout reader and receive()
    private let log = MCPCLogging.logger("transport.stdio") // Component logger

    init( // Configure transport before connect()
        command: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: String? = nil,
        logStderr: Bool = false
    ) {
        self.command = command // Store executable
        self.arguments = arguments // Store args
        self.environment = environment // Store env map
        self.workingDirectory = workingDirectory // Store optional cwd
        self.logStderr = logStderr // Store stderr logging preference
    }

    func connect() async throws { // Spawn subprocess and start reader/drainer tasks
        let proc = Process() // Foundation wrapper around posix_spawn/exec
        proc.executableURL = URL(fileURLWithPath: command) // Path to binary
        proc.arguments = arguments // argv for child
        proc.environment = environment // env for child
        if let workingDirectory, !workingDirectory.isEmpty { // Set cwd when provided
            proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        }

        let stdin = Pipe() // Pipe for writing to child stdin
        let stdout = Pipe() // Pipe for reading child stdout
        let stderr = Pipe() // Pipe for reading child stderr (must be drained)

        proc.standardInput = stdin // Wire stdin pipe
        proc.standardOutput = stdout // Wire stdout pipe
        proc.standardError = stderr // Wire stderr pipe

        do {
            try proc.run() // Launch the child process
        } catch {
            log.error( // Log spawn failure
                "Failed to spawn subprocess",
                metadata: [
                    "command": .string(command),
                    "error": .string(error.localizedDescription),
                ]
            )
            throw MCPError.processSpawnFailed(reason: error.localizedDescription) // Map to MCP error
        }

        log.info( // Log successful spawn
            "Spawned subprocess",
            metadata: [
                "command": .string(command),
                "pid": .stringConvertible(proc.processIdentifier),
                "args": .string(arguments.joined(separator: " ")),
            ]
        )

        process = proc // Remember process for send/disconnect
        stdinPipe = stdin // Remember stdin pipe for send()
        isConnected = true // Mark transport connected

        let stdoutHandle = stdout.fileHandleForReading // Readable end of stdout pipe
        let buffer = lineBuffer // Capture buffer for detached task
        stdoutReaderTask = Task.detached { [weak self] in // `Task.detached` runs off actor/main thread
            await self?.readStdoutLoop(handle: stdoutHandle, process: proc, buffer: buffer) // Line-delimited stdout reader
        }

        let stderrHandle = stderr.fileHandleForReading // Readable stderr end
        let shouldLogStderr = logStderr // Capture flag for closure
        let processID = proc.processIdentifier // PID for waitpid polling
        stderrDrainTask = Task.detached { // Drain stderr so pipe cannot fill and block child
            while !Task.isCancelled { // Loop until task cancelled on disconnect
                let chunk = stderrHandle.availableData // Read whatever stderr has right now
                if chunk.isEmpty { // No data currently available
                    var status: Int32 = 0 // Exit status out-parameter for waitpid
                    let exited = waitpid(processID, &status, WNOHANG) > 0 // Non-blocking check if child exited
                    if exited {
                        break // Stop draining when process is gone
                    }
                    try? await Task.sleep(for: .milliseconds(10)) // Brief sleep before polling again
                    continue
                }
                if shouldLogStderr, let text = String(data: chunk, encoding: .utf8), !text.isEmpty { // Optional forward to stderr
                    FileHandle.standardError.write(Data(text.utf8)) // Write bytes to our stderr
                }
            }
        }
    }

    func disconnect() async throws { // Tear down child process and background tasks
        guard isConnected || process != nil else { return } // No-op if never connected
        isConnected = false // Stop receive() from waiting indefinitely
        log.debug("Disconnecting stdio transport")

        stdinPipe?.fileHandleForWriting.closeFile() // Close stdin so child may exit on EOF

        stdoutReaderTask?.cancel() // Cancel stdout reader loop
        stderrDrainTask?.cancel() // Cancel stderr drainer
        if let stdoutReaderTask { // Wait for reader task to finish cleanup
            _ = await stdoutReaderTask.value // `await` task completion
        }
        stdoutReaderTask = nil // Release task reference
        stderrDrainTask = nil

        if let proc = process, proc.isRunning { // Give child a moment to exit gracefully
            try await Task.sleep(for: .milliseconds(100))
        }

        if let proc = process, proc.isRunning { // Ask nicely to terminate
            proc.terminate()
            try await Task.sleep(for: .milliseconds(100))
        }

        #if os(macOS) // SIGKILL only on macOS branch here
        if let proc = process, proc.isRunning { // Force kill if still alive
            kill(proc.processIdentifier, SIGKILL)
        }
        #endif

        process = nil // Drop process handle
        stdinPipe = nil // Drop stdin pipe

        await lineBuffer.cancelWaiters() // Wake/fail any pending receive() waiters
        log.debug("Stdio transport disconnected")
    }

    func send(_ data: Data) async throws { // Write one JSON-RPC message line to child stdin
        guard isConnected, let pipe = stdinPipe, let proc = process else { // Must be connected with pipes
            throw MCPError.connectionFailed(reason: "SubprocessStdioTransport is not connected")
        }

        guard proc.isRunning else { // Child already exited
            isConnected = false
            throw MCPError.transportClosed
        }

        var messageData = data // Copy so we can append newline
        messageData.append(0x0A) // Append '\n' newline delimiter for line-based protocol
        try pipe.fileHandleForWriting.write(contentsOf: messageData) // Write bytes to stdin pipe
        log.trace("Sent message", metadata: ["bytes": .stringConvertible(messageData.count)]) // Trace-level log
    }

    func receive() async throws -> Data { // Dequeue next complete line from stdout buffer
        let data = try await lineBuffer.dequeueOrWait(isConnected: isConnected) // Suspend until a line arrives
        log.trace("Received message", metadata: ["bytes": .stringConvertible(data.count)])
        return data // Return one message's raw bytes (without trailing newline)
    }

    private func readStdoutLoop(handle: FileHandle, process: Process, buffer: LineBuffer) async { // Background stdout reader
        var readBuffer = "" // Accumulates partial line across chunk reads

        while !Task.isCancelled, isConnected { // Read until cancelled or disconnected
            let chunk = handle.availableData // Non-blocking read chunk from stdout

            if chunk.isEmpty { // No bytes right now
                if !process.isRunning { // Child exited: fail pending receivers
                    await failPendingReceivers()
                    return
                }
                try? await Task.sleep(for: .milliseconds(10)) // Poll again shortly
                continue
            }

            guard let text = String(data: chunk, encoding: .utf8) else { // Ignore non-UTF8 chunks
                continue
            }

            readBuffer.append(text) // Append new text to rolling buffer
            let lines = readBuffer.split(separator: "\n", omittingEmptySubsequences: false) // Split on newlines
            if lines.count <= 1 { // No complete line yet (only a partial tail)
                continue
            }

            readBuffer = String(lines[lines.count - 1]) // Keep trailing partial line in buffer
            for index in 0..<(lines.count - 1) { // Deliver all complete lines
                let line = String(lines[index]) // Convert Substring to String
                guard !line.isEmpty, let data = line.data(using: .utf8) else { // Skip empty/non-UTF8 lines
                    continue
                }
                if let receiver = await buffer.enqueue(data) { // Enqueue line; may resume waiting receiver
                    receiver.resume(returning: data) // Resume suspended receive() with this line
                }
            }
        }
    }

    private func failPendingReceivers() async { // Called when child exits unexpectedly
        isConnected = false // Mark disconnected
        let receivers = await lineBuffer.failAll() // Collect all suspended receive continuations
        for receiver in receivers { // Fail each waiter
            receiver.resume(throwing: MCPError.transportClosed) // Throw transport closed error
        }
    }
}

#endif // End macOS || Linux
