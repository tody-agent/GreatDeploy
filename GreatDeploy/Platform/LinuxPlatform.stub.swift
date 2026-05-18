import Foundation

#if os(Linux)
/// Linux implementation stub — not implemented in v1.
/// Future: implement using Linux Secret Service (libsecret), /proc filesystem, etc.
struct LinuxPlatform: PlatformAdapter {
    static let shared = LinuxPlatform()
    let secretStore: SecretStore = LinuxSecretStore()
    let fileSystem: FileSystem = LinuxFileSystem()
    let processRunner: ProcessRunner = LinuxProcessRunner()
    var appSupportDirectory: URL { fatalError("Not implemented in this release") }
    var logsDirectory: URL { fatalError("Not implemented in this release") }
}

// MARK: - Linux stub implementations

struct LinuxSecretStore: SecretStore {
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

struct LinuxFileSystem: FileSystem {
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

struct LinuxProcessRunner: ProcessRunner {
    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        fatalError("Not implemented in this release")
    }
}
#endif
