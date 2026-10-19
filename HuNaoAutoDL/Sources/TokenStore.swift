import Foundation

enum TokenStore {
    private static let fileManager = FileManager.default

    private static var directoryURL: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("HuNaoAutoDL", isDirectory: true)
    }

    private static var tokenURL: URL? {
        directoryURL?.appendingPathComponent("session.token", isDirectory: false)
    }

    static func loadToken() -> String? {
        guard let tokenURL,
              let data = try? Data(contentsOf: tokenURL),
              let token = String(data: data, encoding: .utf8)
        else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    static func saveToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let directoryURL,
              let tokenURL,
              let data = trimmed.data(using: .utf8)
        else { return false }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directoryURL.path
            )
            try data.write(to: tokenURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tokenURL.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = tokenURL
            try? mutableURL.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    static func deleteToken() {
        guard let tokenURL else { return }
        try? fileManager.removeItem(at: tokenURL)
    }
}
