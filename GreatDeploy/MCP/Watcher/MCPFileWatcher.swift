import Foundation
import Combine
import os.log

/// Event from the file watcher.
struct FileWatcherEvent: Sendable {
    let path: URL
    let eventType: EventType
    let isFromGreatDeploy: Bool
    
    enum EventType: Sendable {
        case write
        case rename
        case delete
    }
}

/// Watches MCP config files for external changes.
/// Uses DispatchSource for file system events with debounce.
final class MCPFileWatcher: @unchecked Sendable {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GreatDeploy", category: "MCPFileWatcher")
    
    /// Combine publisher for events (emits on main thread).
    var events: AnyPublisher<FileWatcherEvent, Never> {
        subject.eraseToAnyPublisher()
    }
    
    private let subject = PassthroughSubject<FileWatcherEvent, Never>()
    private var sources: [URL: DispatchSourceFileSystemObject] = [:]
    private var debounceTimers: [URL: DispatchWorkItem] = [:]
    private var lastGreatDeployWrite: [URL: Date] = [:]
    private let debounceInterval: DispatchTimeInterval = .milliseconds(500)
    private let suppressWindow: TimeInterval = 5.0  // Suppress notifications within 5s of our write
    
    private let queue = DispatchQueue(label: "com.greatdeploy.file-watcher")
    
    /// Start watching the given paths.
    func startWatching(paths: [URL]) {
        queue.sync {
            for path in paths {
                self.startWatching(path: path)
            }
        }
    }
    
    /// Stop watching a specific path.
    func stopWatching(path: URL) {
        queue.sync {
            if let source = self.sources[path] {
                source.cancel()
                self.sources.removeValue(forKey: path)
            }
            self.debounceTimers[path]?.cancel()
            self.debounceTimers.removeValue(forKey: path)
        }
    }
    
    /// Record that GreatDeploy wrote to this path (suppress notifications).
    func recordGreatDeployWrite(path: URL) {
        queue.sync {
            self.lastGreatDeployWrite[path] = Date()
        }
    }
    
    /// Stop watching all paths.
    func stopAll() {
        queue.sync {
            let paths = Array(self.sources.keys)
            for path in paths {
                if let source = self.sources[path] {
                    source.cancel()
                    self.sources.removeValue(forKey: path)
                }
                self.debounceTimers[path]?.cancel()
                self.debounceTimers.removeValue(forKey: path)
            }
        }
    }
    
    deinit {
        stopAll()
    }
    
    private func startWatching(path: URL) {
        guard FileManager.default.fileExists(atPath: path.path) else {
            Self.logger.warning("Path does not exist: \(path.path)")
            return
        }
        
        // Don't watch the same path twice
        guard sources[path] == nil else { return }
        
        let fileDescriptor = open(path.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            Self.logger.error("Failed to open file descriptor for \(path.path)")
            return
        }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.handleEvent(path: path)
        }
        
        source.setCancelHandler {
            close(fileDescriptor)
        }
        
        source.resume()
        sources[path] = source
    }
    
    private func handleEvent(path: URL) {
        // Check if this is from GreatDeploy (within suppress window)
        let shouldSuppress: Bool
        var lastWriteDate: Date?
        
        lastWriteDate = lastGreatDeployWrite[path]
        if let lastWrite = lastWriteDate {
            shouldSuppress = Date().timeIntervalSince(lastWrite) < suppressWindow
        } else {
            shouldSuppress = false
        }
        
        if shouldSuppress {
            Self.logger.info("Suppressing event for GreatDeploy write: \(path.lastPathComponent)")
            return
        }
        
        // Debounce
        debounceTimers[path]?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            let event = FileWatcherEvent(
                path: path,
                eventType: .write,  // Simplified — could detect rename/delete
                isFromGreatDeploy: false
            )
            
            DispatchQueue.main.async {
                self.subject.send(event)
            }
            
            Self.logger.info("External change detected: \(path.lastPathComponent)")
        }
        
        debounceTimers[path] = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
