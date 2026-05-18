import XCTest
import Combine
@testable import GreatDeploy

@MainActor
final class MCPFileWatcherTests: XCTestCase {
    
    private var cancellables: Set<AnyCancellable> = []
    private var tempDir: URL!
    private var tempFile: URL!
    
    override func setUp() {
        super.setUp()
        cancellables.removeAll()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MCPFileWatcherTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempFile = tempDir.appendingPathComponent("test-config.json")
        try? "{}".write(to: tempFile, atomically: true, encoding: .utf8)
    }
    
    override func tearDown() {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Test 1: startWatching creates source for existing path
    
    func testStartWatchingExistingPath() {
        let watcher = MCPFileWatcher()
        var receivedEvents: [FileWatcherEvent] = []
        
        watcher.events
            .sink { event in
                receivedEvents.append(event)
            }
            .store(in: &cancellables)
        
        watcher.startWatching(paths: [tempFile])
        
        // Trigger a file write to generate an event
        try? "modified".write(to: tempFile, atomically: true, encoding: .utf8)
        
        // Wait for debounce (500ms) + buffer
        let expectation = expectation(description: "Event received")
        expectation.assertForOverFulfill = false
        
        watcher.events
            .first()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2.0)
        
        // Clean up
        watcher.stopAll()
    }
    
    // MARK: - Test 2: stopWatching removes source
    
    func testStopWatchingRemovesSource() {
        let watcher = MCPFileWatcher()
        var receivedEvents: [FileWatcherEvent] = []
        
        watcher.events
            .sink { event in
                receivedEvents.append(event)
            }
            .store(in: &cancellables)
        
        watcher.startWatching(paths: [tempFile])
        watcher.stopWatching(path: tempFile)
        
        // Write to file after stopping — should not trigger event
        try? "modified".write(to: tempFile, atomically: true, encoding: .utf8)
        
        // Wait longer than debounce interval
        let expectation = expectation(description: "No events after stop")
        expectation.isInverted = true
        
        watcher.events
            .first()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 1.5)
    }
    
    // MARK: - Test 3: recordGreatDeployWrite suppresses events within 5s
    
    func testRecordGreatDeployWriteSuppressesEvent() {
        let watcher = MCPFileWatcher()
        var receivedEvents: [FileWatcherEvent] = []
        
        watcher.events
            .sink { event in
                receivedEvents.append(event)
            }
            .store(in: &cancellables)
        
        watcher.startWatching(paths: [tempFile])
        watcher.recordGreatDeployWrite(path: tempFile)
        
        // Write to file immediately after recording
        try? "suppressed".write(to: tempFile, atomically: true, encoding: .utf8)
        
        // Wait longer than debounce interval
        let expectation = expectation(description: "No events after GreatDeploy write")
        expectation.isInverted = true
        
        watcher.events
            .first()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 1.5)
        
        watcher.stopAll()
    }
    
    // MARK: - Test 4: stopAll removes all sources
    
    func testStopAllRemovesAllSources() {
        let watcher = MCPFileWatcher()
        let tempFile2 = tempDir.appendingPathComponent("test-config-2.json")
        try? "{}".write(to: tempFile2, atomically: true, encoding: .utf8)
        
        var receivedEvents: [FileWatcherEvent] = []
        
        watcher.events
            .sink { event in
                receivedEvents.append(event)
            }
            .store(in: &cancellables)
        
        watcher.startWatching(paths: [tempFile, tempFile2])
        watcher.stopAll()
        
        // Write to both files — should not trigger events
        try? "modified1".write(to: tempFile, atomically: true, encoding: .utf8)
        try? "modified2".write(to: tempFile2, atomically: true, encoding: .utf8)
        
        // Wait longer than debounce interval
        let expectation = expectation(description: "No events after stopAll")
        expectation.isInverted = true
        
        watcher.events
            .first()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 1.5)
    }
    
    // MARK: - Test 5: Debounce — multiple events within 500ms result in 1 event
    
    func testDebounceMultipleEvents() {
        let watcher = MCPFileWatcher()
        var eventCount = 0
        
        watcher.events
            .sink { _ in
                eventCount += 1
            }
            .store(in: &cancellables)
        
        watcher.startWatching(paths: [tempFile])
        
        // Write multiple times rapidly
        try? "write1".write(to: tempFile, atomically: true, encoding: .utf8)
        try? "write2".write(to: tempFile, atomically: true, encoding: .utf8)
        try? "write3".write(to: tempFile, atomically: true, encoding: .utf8)
        
        // Wait for debounce to fire once
        let expectation = expectation(description: "Debounced event received")
        expectation.assertForOverFulfill = false
        
        var fulfillCount = 0
        watcher.events
            .sink { _ in
                fulfillCount += 1
                if fulfillCount == 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2.0)
        
        // Should have received exactly 1 event despite 3 writes
        XCTAssertEqual(fulfillCount, 1, "Expected exactly 1 debounced event")
        
        watcher.stopAll()
    }
    
    // MARK: - Test 6: Events published through Combine subject
    
    func testEventsPublishedThroughCombine() {
        let watcher = MCPFileWatcher()
        var receivedPath: URL?
        var receivedEventType: FileWatcherEvent.EventType?
        
        let expectation = expectation(description: "Event published through Combine")
        
        watcher.events
            .sink { event in
                receivedPath = event.path
                receivedEventType = event.eventType
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        watcher.startWatching(paths: [tempFile])
        
        // Trigger a write
        try? "combine-test".write(to: tempFile, atomically: true, encoding: .utf8)
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertEqual(receivedPath, tempFile)
        XCTAssertEqual(receivedEventType, .write)
        
        watcher.stopAll()
    }
    
    // MARK: - Test 7: Non-existent path does not crash
    
    func testStartWatchingNonExistentPath() {
        let watcher = MCPFileWatcher()
        let nonExistent = tempDir.appendingPathComponent("does-not-exist.json")
        
        // Should not crash, just log a warning
        watcher.startWatching(paths: [nonExistent])
        
        // No sources should be created
        watcher.stopAll()
    }
}
