import Foundation
import MCPClient

actor LineBuffer {
    private var lines: [Data] = []
    private var waiters: [CheckedContinuation<Data, Error>] = []

    func dequeueOrWait(isConnected: Bool) async throws -> Data {
        try await withTaskCancellationHandler {
            if !lines.isEmpty {
                return lines.removeFirst()
            }
            guard isConnected else {
                throw MCPError.transportClosed
            }
            return try await withCheckedThrowingContinuation { continuation in
                waiters.append(continuation)
            }
        } onCancel: {
            Task { await self.cancelWaiters() }
        }
    }

    func cancelWaiters() {
        let receivers = waiters
        waiters = []
        for receiver in receivers {
            receiver.resume(throwing: CancellationError())
        }
    }

    func enqueue(_ data: Data) -> CheckedContinuation<Data, Error>? {
        if !waiters.isEmpty {
            return waiters.removeFirst()
        }
        lines.append(data)
        return nil
    }

    func failAll() -> [CheckedContinuation<Data, Error>] {
        let receivers = waiters
        waiters = []
        lines = []
        return receivers
    }
}
