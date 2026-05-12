import XCTest
import Foundation

final class SecurityScanTests: XCTestCase {
    
    func testNoSecretFilesTrackedByGit() {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", "cd \(getSourceRoot()) && git ls-files"]
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let trackedFiles = output.components(separatedBy: .newlines)
                let badFiles = [".env", ".dev.vars", ".env.local", ".env.production", "secrets.json"]
                
                let foundBadFiles = badFiles.filter { trackedFiles.contains($0) }
                XCTAssertTrue(foundBadFiles.isEmpty, "Secret files are being tracked by git: \(foundBadFiles.joined(separator: ", "))")
            }
        } catch {
            XCTFail("Failed to run git ls-files: \(error)")
        }
    }
    
    func testGitignoreContainsSecurityPatterns() {
        let rootPath = getSourceRoot()
        let gitignorePath = URL(fileURLWithPath: rootPath).appendingPathComponent(".gitignore")
        
        guard FileManager.default.fileExists(atPath: gitignorePath.path) else {
            XCTFail(".gitignore does not exist in root directory")
            return
        }
        
        do {
            let content = try String(contentsOf: gitignorePath, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            
            XCTAssertTrue(lines.contains(".env"), ".gitignore is missing .env pattern")
        } catch {
            XCTFail("Failed to read .gitignore: \(error)")
        }
    }
    
    func testNoHardcodedSecretsInSourceFiles() {
        let sourcePath = getSourceRoot()
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(atPath: sourcePath)
        
        let dangerousPatterns = [
            "PRIVATE_KEY\\s*[=:]\\s*['\"][a-zA-Z0-9/+=]{20,}['\"]",
            "SERVICE_KEY\\s*[=:]\\s*['\"][a-zA-Z0-9/+=]{20,}['\"]",
            "-----BEGIN.*PRIVATE KEY-----",
            "(?i)api[_-]?key\\s*[=:]\\s*['\"][a-zA-Z0-9]{30,}['\"]",
            "ghp_[a-zA-Z0-9]{36}" // GitHub Personal Access Token pattern
        ]
        
        let compiledPatterns = dangerousPatterns.compactMap { try? NSRegularExpression(pattern: $0) }
        
        while let filePath = enumerator?.nextObject() as? String {
            if filePath.hasSuffix(".swift") && !filePath.contains("SecurityScanTests.swift") {
                let fullPath = URL(fileURLWithPath: sourcePath).appendingPathComponent(filePath)
                
                if let content = try? String(contentsOf: fullPath, encoding: .utf8) {
                    let range = NSRange(location: 0, length: content.utf16.count)
                    
                    for regex in compiledPatterns {
                        let matches = regex.matches(in: content, options: [], range: range)
                        XCTAssertTrue(matches.isEmpty, "Found potential hardcoded secret in \(filePath) matching pattern: \(regex.pattern)")
                    }
                }
            }
        }
    }
    
    // Helper to find the project root path dynamically since XCTest runs in derived data
    private func getSourceRoot() -> String {
        // Find path relative to this source file using #file
        let currentFile = #file
        // /.../GreatDeployTests/SecurityScanTests.swift -> /.../
        let components = currentFile.components(separatedBy: "/")
        // Remove 'SecurityScanTests.swift' and 'GreatDeployTests'
        let rootComponents = components.dropLast(2)
        return rootComponents.joined(separator: "/")
    }
}
