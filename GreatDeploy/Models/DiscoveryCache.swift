import Foundation

public struct DiscoveryCache: Codable {
    public let discoveredAt: Date
    public let skills: [DiscoveredSkill]
    public let toolsScanned: [String]
    public let version: String
    
    public init(skills: [DiscoveredSkill], toolsScanned: [AITool]) {
        self.discoveredAt = Date()
        self.skills = skills
        self.toolsScanned = toolsScanned.map { $0.rawValue }
        self.version = DiscoveryCache.currentVersion
    }
    
    public var toolsScannedEnums: [AITool] {
        toolsScanned.compactMap { AITool(rawValue: $0) }
    }
    
    public static let currentVersion = "1.0"
    public static let cacheFileName = "discovery-cache.json"
    
    public var cacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".greatdeploy")
            .appendingPathComponent(Self.cacheFileName)
    }
    
    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        let dir = cacheURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try data.write(to: cacheURL, options: .atomic)
    }
    
    public static func load() throws -> DiscoveryCache? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".greatdeploy")
            .appendingPathComponent(cacheFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cache = try decoder.decode(DiscoveryCache.self, from: data)
        guard cache.version == currentVersion else { return nil }
        return cache
    }
}