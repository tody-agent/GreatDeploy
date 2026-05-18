import Foundation
@testable import GreatDeploy

/// Test file system that writes to a configurable URL.
final class TestFileSystem: FileSystem, @unchecked Sendable {
    let configURL: URL

    init(configURL: URL) {
        self.configURL = configURL
    }

    func atomicWrite(_ data: Data, to url: URL) throws {
        let parentDir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: [])
    }

    func readData(from url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func backup(_ url: URL) throws -> URL {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).bak.\(timestamp)")
        try FileManager.default.copyItem(at: url, to: backupURL)
        return backupURL
    }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
