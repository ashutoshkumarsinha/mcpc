import Foundation
import MCPClient

// actor = Swift concurrency type; only one task can call its methods at a time (thread-safe).
actor LineBuffer {
    // Lines read from subprocess stdout waiting to be consumed by receive().
    private var lines: [Data] = []
    // Tasks blocked in receive() until a line arrives.
    private var waiters: [CheckedContinuation<Data, Error>] = []

    // Called by transport receive(): return next line or wait until one is enqueued.
    func dequeueOrWait(isConnected: Bool) async throws -> Data {
        try await withTaskCancellationHandler {
            // Fast path: data already buffered.
            if !lines.isEmpty {
                return lines.removeFirst()
            }
            // If transport is closed and buffer empty, fail immediately.
            guard isConnected else {
                throw MCPError.transportClosed
            }
            // Suspend this task until enqueue() delivers a line.
            return try await withCheckedThrowingContinuation { continuation in
                waiters.append(continuation)
            }
        } onCancel: {
            // If caller cancels, wake waiters with CancellationError.
            Task { await self.cancelWaiters() }
        }
    }

    // Resume all waiting receive() calls with cancellation.
    func cancelWaiters() {
        let receivers = waiters
        waiters = []
        for receiver in receivers {
            receiver.resume(throwing: CancellationError())
        }
    }

    // Called by background reader when a new line is read from stdout.
    // Returns a continuation to resume immediately, or nil if line was queued.
    func enqueue(_ data: Data) -> CheckedContinuation<Data, Error>? {
        if !waiters.isEmpty {
            return waiters.removeFirst() // someone is waiting — hand off directly
        }
        lines.append(data) // no waiter — store for later
        return nil
    }

    // Called on disconnect: clear state and return waiters to fail.
    func failAll() -> [CheckedContinuation<Data, Error>] {
        let receivers = waiters
        waiters = []
        lines = []
        return receivers
    }
}
