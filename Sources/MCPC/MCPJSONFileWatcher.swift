import Foundation // FileManager, URL, Dispatch APIs

#if os(macOS) // Compile this file only on macOS

public final class MCPJSONFileWatcher: @unchecked Sendable { // `final` = not subclassable; `@unchecked Sendable` = manually thread-safe
    private let queue = DispatchQueue(label: "mcpc.mcpjson.watcher") // Serial background queue for file events
    private var sources: [DispatchSourceFileSystemObject] = [] // Active kernel file-watch sources
    private var fileDescriptors: [Int32] = [] // Open file descriptors being watched
    private var debounceWorkItems: [String: DispatchWorkItem] = [:] // Pending debounced callbacks keyed by path
    private var watchedTargets: [URL] = [] // URLs we intend to react to when they change
    private let debounceSeconds: TimeInterval // Delay before firing onChange after rapid writes

    public init(debounceSeconds: TimeInterval = 0.5) { // Public initializer with default 0.5s debounce
        self.debounceSeconds = debounceSeconds // Store debounce interval
    }

    deinit { // Called automatically when the watcher is deallocated
        queue.sync { // Run cleanup synchronously on our serial queue
            stopLocked() // Tear down watches (must be called on `queue`)
        }
    }

    public func setWatchURLs(_ urls: [URL], onChange: @escaping @Sendable (URL) -> Void) { // Start watching URLs; `@escaping` = stored closure; `@Sendable` = safe across concurrency domains
        queue.async { // Schedule work on the watcher queue (not the caller's thread)
            self.stopLocked() // Clear any previous watches first
            self.watchedTargets = urls // Remember the logical targets
            for url in urls { // Register a watch for each URL
                self.watch(url: url, onChange: onChange) // Watch file and its parent directory
            }
        }
    }

    public func stop() { // Public API to stop all watching
        queue.async { // Async stop on the watcher queue
            self.stopLocked() // Cancel sources and close descriptors
        }
    }

    private func stopLocked() { // Internal cleanup; caller must hold `queue` execution
        debounceWorkItems.values.forEach { $0.cancel() } // Cancel pending debounced callbacks
        debounceWorkItems.removeAll() // Drop debounce map entries
        sources.forEach { $0.cancel() } // Cancel DispatchSource watchers
        sources.removeAll() // Clear source array
        fileDescriptors.forEach { close($0) } // Close POSIX file descriptors
        fileDescriptors.removeAll() // Clear descriptor list
        watchedTargets = [] // Forget watched targets
    }

    private func watch(url: URL, onChange: @escaping @Sendable (URL) -> Void) { // Set up watches for one logical file
        if FileManager.default.fileExists(atPath: url.path) { // If the file already exists, watch it directly
            addWatch(
                path: url.path,
                eventMask: [.write, .delete, .rename, .extend, .attrib], // React to common mutation events
                target: url, // Logical URL to pass to onChange
                onChange: onChange
            )
        }

        let parent = url.deletingLastPathComponent() // Parent directory (catches create/rename into place)
        addWatch(
            path: parent.path,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            target: url,
            onChange: onChange
        )
    }

    private func addWatch(
        path: String, // Filesystem path to open for events-only
        eventMask: DispatchSource.FileSystemEvent, // Which vnode events to subscribe to
        target: URL, // Logical changed file (may differ from `path` when watching parent dir)
        onChange: @escaping @Sendable (URL) -> Void // Callback after debounce
    ) {
        let descriptor = open(path, O_EVTONLY) // Open path for event notification only (no read/write)
        guard descriptor >= 0 else { return } // `guard` bails if open failed (e.g. permissions)

        let source = DispatchSource.makeFileSystemObjectSource( // Create a DispatchSource for vnode events
            fileDescriptor: descriptor,
            eventMask: eventMask,
            queue: queue // Deliver events on our serial queue
        )

        source.setEventHandler { [weak self] in // `[weak self]` avoids retain cycles with the watcher
            self?.scheduleDebouncedChange(for: target, onChange: onChange) // Debounce rapid filesystem churn
        }
        source.setCancelHandler { [descriptor] in // Run when the source is cancelled
            close(descriptor) // Close FD on cancel (capture descriptor by value)
        }

        fileDescriptors.append(descriptor) // Track FD so stopLocked can close it
        sources.append(source) // Track source so we can cancel it later
        source.resume() // Start receiving events
    }

    private func scheduleDebouncedChange(for url: URL, onChange: @escaping @Sendable (URL) -> Void) { // Coalesce bursts of events
        let key = url.path // Debounce key = filesystem path string
        debounceWorkItems[key]?.cancel() // Cancel any previously scheduled callback for this path

        let work = DispatchWorkItem { [weak self] in // New debounced work item
            guard let self else { return } // Exit if watcher was deallocated
            self.debounceWorkItems[key] = nil // Clear slot once work runs
            guard FileManager.default.fileExists(atPath: url.path) else { return } // Ignore if file was deleted
            onChange(url) // Notify consumer that the file changed
        }
        debounceWorkItems[key] = work // Store work item so a newer event can cancel it
        queue.asyncAfter(deadline: .now() + debounceSeconds, execute: work) // Run after debounce delay
    }
}

#endif // End macOS-only compilation
