import XCTest
@testable import GreatDeploy

final class VaultStoreTests: XCTestCase {
    
    private var sut: VaultStore!
    
    override func setUp() {
        super.setUp()
        sut = VaultStore.shared
        // Clean up test data
        try? sut.deleteAll()
    }
    
    override func tearDown() {
        try? sut.deleteAll()
        sut = nil
        super.tearDown()
    }
    
    // MARK: - CRUD Tests
    
    func testSaveAndLoadItem() throws {
        let item = VaultItem(kind: .githubAccount, displayName: "Test Account")
        try sut.save(item)
        
        let loaded = try sut.load(id: item.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.displayName, "Test Account")
        XCTAssertEqual(loaded?.kind, .githubAccount)
    }
    
    func testLoadAllReturnsAllItems() throws {
        let item1 = VaultItem(kind: .githubAccount, displayName: "Account 1")
        let item2 = VaultItem(kind: .cloudflareAccount, displayName: "Account 2")
        let item3 = VaultItem(kind: .mcpServer, displayName: "MCP Server")
        
        try sut.save(item1)
        try sut.save(item2)
        try sut.save(item3)
        
        let all = try sut.loadAll()
        XCTAssertEqual(all.count, 3)
    }
    
    func testLoadByKind() throws {
        let github = VaultItem(kind: .githubAccount, displayName: "GitHub")
        let cf = VaultItem(kind: .cloudflareAccount, displayName: "Cloudflare")
        let mcp = VaultItem(kind: .mcpServer, displayName: "MCP")
        
        try sut.save(github)
        try sut.save(cf)
        try sut.save(mcp)
        
        let githubItems = try sut.loadByKind(.githubAccount)
        XCTAssertEqual(githubItems.count, 1)
        XCTAssertEqual(githubItems.first?.displayName, "GitHub")
    }
    
    func testDeleteItem() throws {
        let item = VaultItem(kind: .skill, displayName: "Test Skill")
        try sut.save(item)
        
        try sut.delete(id: item.id)
        
        let loaded = try sut.load(id: item.id)
        XCTAssertNil(loaded)
    }
    
    func testUpdateItem() throws {
        var item = VaultItem(kind: .githubAccount, displayName: "Original")
        try sut.save(item)
        
        item.displayName = "Updated"
        item.updatedAt = Date()
        try sut.save(item)
        
        let loaded = try sut.load(id: item.id)
        XCTAssertEqual(loaded?.displayName, "Updated")
    }
    
    func testDeleteAll() throws {
        try sut.save(VaultItem(kind: .githubAccount, displayName: "A"))
        try sut.save(VaultItem(kind: .skill, displayName: "B"))
        
        try sut.deleteAll()
        
        let all = try sut.loadAll()
        XCTAssertTrue(all.isEmpty)
    }
    
    // MARK: - Metadata Tests
    
    func testMetaSetAndGet() throws {
        try sut.setMeta("test_value", forKey: "test_key")
        let value = try sut.getMeta(forKey: "test_key")
        XCTAssertEqual(value, "test_value")
    }
    
    func testMetaOverwrite() throws {
        try sut.setMeta("first", forKey: "key")
        try sut.setMeta("second", forKey: "key")
        
        let value = try sut.getMeta(forKey: "key")
        XCTAssertEqual(value, "second")
    }
    
    func testMetaDelete() throws {
        try sut.setMeta("value", forKey: "key")
        try sut.deleteMeta(forKey: "key")
        
        let value = try sut.getMeta(forKey: "key")
        XCTAssertNil(value)
    }
    
    // MARK: - Count Tests
    
    func testCountAll() throws {
        try sut.save(VaultItem(kind: .githubAccount, displayName: "A"))
        try sut.save(VaultItem(kind: .skill, displayName: "B"))
        
        let count = try sut.count()
        XCTAssertEqual(count, 2)
    }
    
    func testCountByKind() throws {
        try sut.save(VaultItem(kind: .githubAccount, displayName: "A"))
        try sut.save(VaultItem(kind: .githubAccount, displayName: "B"))
        try sut.save(VaultItem(kind: .skill, displayName: "C"))
        
        let githubCount = try sut.count(kind: .githubAccount)
        let skillCount = try sut.count(kind: .skill)
        
        XCTAssertEqual(githubCount, 2)
        XCTAssertEqual(skillCount, 1)
    }
    
    // MARK: - Metadata Persistence in Item
    
    func testItemMetadataPersists() throws {
        var item = VaultItem(kind: .githubAccount, displayName: "Test")
        item.metadata = ["githubUsername": "testuser", "gitUserEmail": "test@example.com"]
        try sut.save(item)
        
        let loaded = try sut.load(id: item.id)
        XCTAssertEqual(loaded?.metadata["githubUsername"], "testuser")
        XCTAssertEqual(loaded?.metadata["gitUserEmail"], "test@example.com")
    }
}
