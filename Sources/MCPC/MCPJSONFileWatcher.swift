import Foundation

#if os(macOS)

public final class MCPJSONFileWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "mcpc.mcpjson.watcher")
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private var debounceWorkItems: [String: DispatchWorkItem] = [:]
    private var watchedTargets: [URL] = []
    private let debounceSeconds: TimeInterval

    public init(debounceSeconds: TimeInterval = 0.5) {
        self.debounceSeconds = debounceSeconds
    }

    deinit {
        queue.sync {
            stopLocked()
        }
    }

    public func setWatchURLs(_ urls: [URL], onChange: @escaping @Sendable (URL) -> Void) {
        queue.async {
            self.stopLocked()
            self.watchedTargets = urls
            for url in urls {
                self.watch(url: url, onChange: onChange)
            }
        }
    }

    public func stop() {
        queue.async {
            self.stopLocked()
        }
    }

    private func stopLocked() {
        debounceWorkItems.values.forEach { $0.cancel() }
        debounceWorkItems.removeAll()
        sources.forEach { $0.cancel() }
        sources.removeAll()
        fileDescriptors.forEach { close($0) }
        fileDescriptors.removeAll()
        watchedTargets = []
    }

    private func watch(url: URL, onChange: @escaping @Sendable (URL) -> Void) {
        if FileManager.default.fileExists(atPath: url.path) {
            addWatch(
                path: url.path,
                eventMask: [.write, .delete, .rename, .extend, .attrib],
                target: url,
                onChange: onChange
            )
        }

        let parent = url.deletingLastPathComponent()
        addWatch(
            path: parent.path,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            target: url,
            onChange: onChange
        )
    }

    private func addWatch(
        path: String,
        eventMask: DispatchSource.FileSystemEvent,
        target: URL,
        onChange: @escaping @Sendable (URL) -> Void
    ) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: eventMask,
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.scheduleDebouncedChange(for: target, onChange: onChange)
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }

        fileDescriptors.append(descriptor)
        sources.append(source)
        source.resume()
    }

    private func scheduleDebouncedChange(for url: URL, onChange: @escaping @Sendable (URL) -> Void) {
        let key = url.path
        debounceWorkItems[key]?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.debounceWorkItems[key] = nil
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            onChange(url)
        }
        debounceWorkItems[key] = work
        queue.asyncAfter(deadline: .now() + debounceSeconds, execute: work)
    }
}

#endif
