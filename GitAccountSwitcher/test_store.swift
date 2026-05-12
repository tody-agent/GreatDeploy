import Foundation

// Copying necessary structs to decode
struct GitAccount: Codable {
    var id: UUID
    var displayName: String
    var githubUsername: String
    var personalAccessToken: String?
    var gitUserName: String
    var gitUserEmail: String
    var isActive: Bool
    var createdAt: Date
    var lastUsedAt: Date?
}

let defaults = UserDefaults.standard
defaults.addSuite(named: "com.gitaccountswitcher.app")

if let data = defaults.data(forKey: "savedAccounts") {
    print("Found data blob of size \(data.count)")
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
        let accounts = try decoder.decode([GitAccount].self, from: data)
        print("Successfully decoded \(accounts.count) accounts.")
        for (i, acc) in accounts.enumerated() {
            print("Account \(i+1): \(acc.githubUsername) (Active: \(acc.isActive))")
        }
    } catch {
        print("Failed to decode: \(error)")
    }
} else if let array = defaults.array(forKey: "savedAccounts") {
    print("Found array of dictionaries: \(array.count) items")
} else {
    print("No savedAccounts found in UserDefaults.")
}
