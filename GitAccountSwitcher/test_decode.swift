import Foundation

struct GitAccount: Identifiable, Equatable, Hashable, Codable {
    var id: UUID
    var displayName: String
    var githubUsername: String
    var personalAccessToken: String
    var gitUserName: String
    var gitUserEmail: String
    var isActive: Bool
    var createdAt: Date
    var lastUsedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id, displayName, githubUsername
        case gitUserName, gitUserEmail, isActive, createdAt, lastUsedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        githubUsername = try container.decode(String.self, forKey: .githubUsername)
        personalAccessToken = ""
        gitUserName = try container.decode(String.self, forKey: .gitUserName)
        gitUserEmail = try container.decode(String.self, forKey: .gitUserEmail)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }
}

let json = """
[{"gitUserEmail":"tracuuphat@gmail.com","displayName":"tody-agent","githubUsername":"tody-agent","isActive":true,"id":"A2F69FE8-1253-476E-A75A-9B23A9E9307F","gitUserName":"tody-agent","createdAt":"2026-05-12T14:16:02Z","lastUsedAt":"2026-05-12T14:43:13Z"},{"gitUserEmail":"hailm@boxme.asia","displayName":"omisocial","githubUsername":"omisocial","isActive":false,"id":"60AA4969-4527-4C17-BE15-E781B94C2832","gitUserName":"omisocial","createdAt":"2026-05-12T14:18:13Z","lastUsedAt":"2026-05-12T14:43:11Z"}]
"""
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
do {
    let accounts = try decoder.decode([GitAccount].self, from: json.data(using: .utf8)!)
    print("Decoded \(accounts.count) accounts")
    for acc in accounts {
        print("- \(acc.displayName) (active: \(acc.isActive))")
    }
} catch {
    print("Decoding error: \(error)")
}
