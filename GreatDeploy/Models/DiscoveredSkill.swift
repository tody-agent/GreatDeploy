import Foundation
import CommonCrypto

public struct DiscoveredSkill: Identifiable, Codable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let content: String
    public let sourceTool: String
    public let sourcePath: String
    public let lastModified: Date
    
    public init(name: String, description: String, content: String, sourceTool: AITool, sourcePath: URL, lastModified: Date) {
        self.id = Self.computeId(content: content)
        self.name = name
        self.description = description
        self.content = content
        self.sourceTool = sourceTool.rawValue
        self.sourcePath = sourcePath.path
        self.lastModified = lastModified
    }
    
    public var sourceToolEnum: AITool? {
        AITool(rawValue: sourceTool)
    }
    
    private static func computeId(content: String) -> String {
        let inputData = Data(content.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        inputData.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}