import Foundation

#if os(Windows)
/// Windows implementation stub — not implemented in v1.
/// Future: implement using Windows Credential Manager, Win32 filesystem, etc.
struct WindowsPlatform: PlatformAdapter {
    static let shared = WindowsPlatform()
    let secretStore: SecretStore = WindowsSecretStore()
    let fileSystem: FileSystem = WindowsFileSystem()
    let processRunner: ProcessRunner = WindowsProcessRunner()
    var appSupportDirectory: URL { fatalError("Not implemented in this release") }
    var logsDirectory: URL { fatalError("Not implemented in this release") }
}

// MARK: - Windows stub implementations

struct WindowsSecretStore: SecretStore {
    func read(service: String, account: String) throws -> String? {
        fatalError("Not implemented in this release")
    }
    func write(service: String, account: String, value: String) throws {
        fatalError("Not implemented in this release")
    }
    func delete(service: String, account: String) throws {
        fatalError("Not implemented in this release")
    }
}

struct WindowsFileSystem: FileSystem {
    func atomicWrite(data: Data, to url: URL) throws {
        fatalError("Not implemented in this release")
    }
    func readData(from url: URL) -> Data? {
        fatalError("Not implemented in this release")
    }
    func exists(_ url: URL) -> Bool {
        fatalError("Not implemented in this release")
    }
    func backup(_ url: URL) throws -> URL {
        fatalError("Not implemented in this release")
    }
    func createDirectory(at url: URL) throws {
        fatalError("Not implemented in this release")
    }
}

struct WindowsProcessRunner: ProcessRunner {
    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        fatalError("Not implemented in this release")
    }
}
#endif
