import Foundation
import HarborCore

/// Access only to explicitly chosen files/folders, remembered as macOS bookmarks.
@MainActor final class FolderAccess {
    enum Role: String { case source, destination }
    private let defaults = UserDefaults.standard

    func rememberSources(_ urls: [URL]) throws -> [URL] {
        let data = try urls.map { try $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
        let resolved = try data.map(resolve)
        defaults.set(data, forKey: "selectedSources")
        defaults.removeObject(forKey: "folder.source")
        return resolved
    }
    func restoreSources() throws -> [URL] {
        if let data = defaults.array(forKey: "selectedSources") as? [Data] { return try data.map(resolve) }
        if let previous = try restore(.source) { return try rememberSources([previous]) }
        return []
    }
    @discardableResult func remember(_ url: URL, for role: Role) throws -> URL {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        let resolved = try resolve(data)
        defaults.set(data, forKey: "folder.\(role.rawValue)")
        return resolved
    }
    private func resolve(_ data: Data) throws -> URL {
        var stale = false
        return try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    }
    func restore(_ role: Role) throws -> URL? {
        guard let data = defaults.data(forKey: "folder.\(role.rawValue)") else { return nil }
        return try resolve(data)
    }
    func forget() {
        for role in [Role.source, .destination] { forget(role) }
    }
    func forget(_ role: Role) {
        defaults.removeObject(forKey: "folder.\(role.rawValue)")
        if role == .source { defaults.removeObject(forKey: "selectedSources") }
    }
    nonisolated static func withAccess<T>(_ urls: [URL], _ action: () throws -> T) rethrows -> T {
        let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
        return try action()
    }
}
