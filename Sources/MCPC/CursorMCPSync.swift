import Foundation // Sets, dictionaries, sorting, strings

public struct CursorMCPSyncResult: Sendable { // Result of syncing Cursor mcp.json into AppConfig; `Sendable` = safe across tasks
    public let config: AppConfig // Updated configuration after merge
    public let syncedServerNames: [String] // Names managed by Cursor JSON sync
    public let preview: CursorMCPImportPreview // Parsed import preview (servers + warnings)
    public let added: [String] // Newly added server names
    public let updated: [String] // Existing servers whose config changed
    public let removed: [String] // Previously synced servers removed from JSON

    public init( // Memberwise public initializer
        config: AppConfig,
        syncedServerNames: [String],
        preview: CursorMCPImportPreview,
        added: [String],
        updated: [String],
        removed: [String]
    ) {
        self.config = config // Store merged config
        self.syncedServerNames = syncedServerNames // Store managed name list
        self.preview = preview // Store parse preview
        self.added = added // Store added names
        self.updated = updated // Store updated names
        self.removed = removed // Store removed names
    }
}

public enum CursorMCPPaths { // Helpers for resolving Cursor mcp.json watch paths
    public static let defaultRelativePaths = [ // Default locations when none configured
        "~/.cursor/mcp.json", // User-global Cursor MCP config
        ".cursor/mcp.json", // Project-local Cursor MCP config
    ]

    public static func resolvedWatchURLs( // Turn configured path strings into unique file URLs
        configuredPaths: [String],
        configURL: URL // config.toml location (for resolving relative paths)
    ) -> [URL] {
        let paths = configuredPaths.isEmpty ? defaultRelativePaths : configuredPaths // Fall back to defaults
        var seen = Set<String>() // Track normalized paths to deduplicate
        var urls: [URL] = [] // Output URL list

        for path in paths { // Expand each configured path
            let url = expand(path, relativeTo: configURL).standardizedFileURL // Resolve ~, relative, absolute
            guard seen.insert(url.path).inserted else { continue } // Skip duplicates; `inserted` is true only first time
            urls.append(url) // Keep unique watch target
        }
        return urls // Final deduplicated watch list
    }

    public static func expand(_ path: String, relativeTo configURL: URL) -> URL { // Expand ~ and relative paths
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines) // Strip surrounding whitespace
        if trimmed.hasPrefix("~/") { // Home-relative path
            let relative = String(trimmed.dropFirst(2)) // Remove "~/"
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(relative) // Append remainder under home directory
        }
        if trimmed.hasPrefix("/") { // Absolute filesystem path
            return URL(fileURLWithPath: trimmed) // Build file URL from absolute path
        }
        return configURL.deletingLastPathComponent().appendingPathComponent(trimmed) // Relative to config.toml directory
    }
}

public enum CursorMCPSync { // Merge Cursor JSON into config.toml-managed servers
    public static func sync( // Main sync entry point
        json: String, // Raw Cursor mcp.json text
        into config: AppConfig, // Starting config to merge into
        managedServerNames: [String], // Names previously imported/synced from JSON
        onConflict: MergeConflictPolicy = .replace // How to handle name collisions (default replace)
    ) throws -> CursorMCPSyncResult {
        let preview = try CursorMCPConfigImporter.parse(json: json) // Parse JSON into ServerConfig list
        let importedNames = Set(preview.servers.map(\.name)) // Set of names in the JSON import
        let managed = Set(managedServerNames) // Set of names we already manage via sync
        let beforeByName = Dictionary(uniqueKeysWithValues: config.servers.map { ($0.name, $0) }) // Snapshot before merge

        var working = config // Mutable copy we will edit
        let removed = managed.subtracting(importedNames).sorted() // Managed names no longer present in JSON
        working.servers.removeAll { removed.contains($0.name) } // Drop removed servers from config

        let mergeResult = mergeTracked( // Merge imported servers according to conflict policy
            imported: preview.servers,
            into: working,
            managed: managed,
            onConflict: onConflict
        )
        working = mergeResult.config // Take merged config

        var seen = Set<String>() // Detect duplicate server names after merge
        for server in working.servers { // Validate every remaining server entry
            if seen.contains(server.name) { // Duplicate name is a hard error
                throw AppConfigError.duplicateServerName(server.name)
            }
            seen.insert(server.name) // Remember seen name
            try server.validate() // Ensure transport-specific required fields exist
        }

        if working.client.defaultServer.isEmpty // Fix default server if missing or stale
            || !working.servers.contains(where: { $0.name == working.client.defaultServer }) {
            working.client.defaultServer = working.servers.first?.name ?? "" // Pick first server or empty string
        }

        let syncedNames: [String] // Final list of JSON-managed server names to persist
        switch onConflict { // Policy affects which names count as "synced"
        case .replace:
            syncedNames = mergeResult.newManaged.sorted() // All merged managed names
        case .skip:
            syncedNames = Array(managed.union(importedNames.filter { !beforeByName.keys.contains($0) })).sorted() // Keep old managed + newly added only
        }

        working.client.mcpJSONSyncedServers = syncedNames // Persist managed-name tracking in client settings

        let added = importedNames.subtracting(managed).subtracting(Set(beforeByName.keys)).sorted() // Brand-new names
        let updated = importedNames.filter { name in // Names that existed and changed
            guard let previous = beforeByName[name] else { return false } // Skip if not previously in config
            guard let next = working.servers.first(where: { $0.name == name }) else { return false } // Skip if missing after merge
            return previous != next // True when ServerConfig value changed
        }.sorted()

        return CursorMCPSyncResult( // Package everything for the caller/UI
            config: working,
            syncedServerNames: syncedNames,
            preview: preview,
            added: added,
            updated: updated,
            removed: removed
        )
    }

    private static func mergeTracked( // Merge imported servers and track managed names
        imported: [ServerConfig],
        into config: AppConfig,
        managed: Set<String>,
        onConflict: MergeConflictPolicy
    ) -> (config: AppConfig, newManaged: Set<String>) { // Returns tuple of merged config + managed set
        var merged = config // Working copy
        var byName = Dictionary(uniqueKeysWithValues: merged.servers.map { ($0.name, $0) }) // Name -> server map
        var newManaged = managed // Start from existing managed names

        for server in imported { // Apply each imported server
            switch onConflict {
            case .skip where byName[server.name] != nil: // Skip when name exists and policy is .skip
                continue // Leave existing entry untouched
            case .replace, .skip: // `.replace` always writes; `.skip` only when name absent (handled above)
                byName[server.name] = server // Upsert imported server
                newManaged.insert(server.name) // Mark name as JSON-managed
            }
        }

        merged.servers = byName.values.sorted { $0.name < $1.name } // Stable sorted server list
        return (merged, newManaged) // Return merged config and updated managed set
    }
}
