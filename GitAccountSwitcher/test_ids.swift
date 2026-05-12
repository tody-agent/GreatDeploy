import Foundation

struct GitAccount: Codable {
    var id: UUID
    var githubUsername: String
    var isActive: Bool
}

let defaults = UserDefaults.standard
defaults.addSuite(named: "com.gitaccountswitcher.app")

if let data = defaults.data(forKey: "savedAccounts") {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let accounts = try! decoder.decode([GitAccount].self, from: data)
    for acc in accounts {
        print("\(acc.githubUsername) - \(acc.id)")
    }
}
