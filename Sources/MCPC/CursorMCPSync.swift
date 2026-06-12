import Foundation

public struct CursorMCPSyncResult: Sendable {
    public let config: AppConfig
    public let syncedServerNames: [String]
    public let preview: CursorMCPImportPreview
    public let added: [String]
    public let updated: [String]
    public let removed: [String]

    public init(
        config: AppConfig,
        syncedServerNames: [String],
        preview: CursorMCPImportPreview,
        added: [String],
        updated: [String],
        removed: [String]
    ) {
        self.config = config
        self.syncedServerNames = syncedServerNames
        self.preview = preview
        self.added = added
        self.updated = updated
        self.removed = removed
    }
}

public enum CursorMCPPaths {
    public static let defaultRelativePaths = [
        "~/.cursor/mcp.json",
        ".cursor/mcp.json",
    ]

    public static func resolvedWatchURLs(
        configuredPaths: [String],
        configURL: URL
    ) -> [URL] {
        let paths = configuredPaths.isEmpty ? defaultRelativePaths : configuredPaths
        var seen = Set<String>()
        var urls: [URL] = []

        for path in paths {
            let url = expand(path, relativeTo: configURL).standardizedFileURL
            guard seen.insert(url.path).inserted else { continue }
            urls.append(url)
        }
        return urls
    }

    public static func expand(_ path: String, relativeTo configURL: URL) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("~/") {
            let relative = String(trimmed.dropFirst(2))
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(relative)
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        return configURL.deletingLastPathComponent().appendingPathComponent(trimmed)
    }
}

public enum CursorMCPSync {
    public static func sync(
        json: String,
        into config: AppConfig,
        managedServerNames: [String],
        onConflict: MergeConflictPolicy = .replace
    ) throws -> CursorMCPSyncResult {
        let preview = try CursorMCPConfigImporter.parse(json: json)
        let importedNames = Set(preview.servers.map(\.name))
        let managed = Set(managedServerNames)
        let beforeByName = Dictionary(uniqueKeysWithValues: config.servers.map { ($0.name, $0) })

        var working = config
        let removed = managed.subtracting(importedNames).sorted()
        working.servers.removeAll { removed.contains($0.name) }

        let mergeResult = mergeTracked(
            imported: preview.servers,
            into: working,
            managed: managed,
            onConflict: onConflict
        )
        working = mergeResult.config

        var seen = Set<String>()
        for server in working.servers {
            if seen.contains(server.name) {
                throw AppConfigError.duplicateServerName(server.name)
            }
            seen.insert(server.name)
            try server.validate()
        }

        if working.client.defaultServer.isEmpty
            || !working.servers.contains(where: { $0.name == working.client.defaultServer }) {
            working.client.defaultServer = working.servers.first?.name ?? ""
        }

        let syncedNames: [String]
        switch onConflict {
        case .replace:
            syncedNames = mergeResult.newManaged.sorted()
        case .skip:
            syncedNames = Array(managed.union(importedNames.filter { !beforeByName.keys.contains($0) })).sorted()
        }

        working.client.mcpJSONSyncedServers = syncedNames

        let added = importedNames.subtracting(managed).subtracting(Set(beforeByName.keys)).sorted()
        let updated = importedNames.filter { name in
            guard let previous = beforeByName[name] else { return false }
            guard let next = working.servers.first(where: { $0.name == name }) else { return false }
            return previous != next
        }.sorted()

        return CursorMCPSyncResult(
            config: working,
            syncedServerNames: syncedNames,
            preview: preview,
            added: added,
            updated: updated,
            removed: removed
        )
    }

    private static func mergeTracked(
        imported: [ServerConfig],
        into config: AppConfig,
        managed: Set<String>,
        onConflict: MergeConflictPolicy
    ) -> (config: AppConfig, newManaged: Set<String>) {
        var merged = config
        var byName = Dictionary(uniqueKeysWithValues: merged.servers.map { ($0.name, $0) })
        var newManaged = managed

        for server in imported {
            switch onConflict {
            case .skip where byName[server.name] != nil:
                continue
            case .replace, .skip:
                byName[server.name] = server
                newManaged.insert(server.name)
            }
        }

        merged.servers = byName.values.sorted { $0.name < $1.name }
        return (merged, newManaged)
    }
}
