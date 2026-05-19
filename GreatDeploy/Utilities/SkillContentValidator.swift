import Foundation

struct SkillContentValidator {
    private let suspiciousPatterns: [String] = [
        "eval\\s*\\(",
        "exec\\s*\\(",
        "subprocess\\s*\\.",
        "shell=True",
        "os\\.system\\s*\\(",
        "os\\.popen\\s*\\(",
        "Runtime\\.getRuntime\\(\\)\\.exec",
        "ProcessBuilder",
        "os\\.spawn",
        "child_process\\.execSync"
    ]
    
    private let secretPatterns: [String] = [
        "(?i)(api[_-]?key|secret[_-]?key|access[_-]?token)\\s*[:=]\\s*['\"]",
        "gh[pousr]_[A-Za-z0-9]{36,}",
        "(?i)bearer\\s+[A-Za-z0-9\\-_\\.]+",
        "(?i)token['\"\\s]+[:=]+['\"\\s]+[A-Za-z0-9\\-_\\.]{20,}"
    ]
    
    struct ValidationResult {
        let isValid: Bool
        let warnings: [String]
        
        var hasWarnings: Bool { !warnings.isEmpty }
    }
    
    func validate(_ content: String) -> ValidationResult {
        var warnings: [String] = []
        
        for pattern in suspiciousPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(content.startIndex..., in: content)
                if regex.firstMatch(in: content, options: [], range: range) != nil {
                    warnings.append("Suspicious pattern detected: potentially dangerous code pattern")
                    break
                }
            }
        }
        
        for pattern in secretPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(content.startIndex..., in: content)
                if regex.firstMatch(in: content, options: [], range: range) != nil {
                    warnings.append("Potential secret or token detected in content")
                    break
                }
            }
        }
        
        return ValidationResult(isValid: warnings.isEmpty, warnings: warnings)
    }
    
    func scanForSecrets(_ content: String) -> [String] {
        var found: [String] = []
        
        let patterns = [
            ("GitHub Token", "(?i)gh[pousr]_[A-Za-z0-9]{36,}"),
            ("Bearer Token", "(?i)bearer\\s+[A-Za-z0-9\\-_\\.]+"),
            ("API Key Pattern", "(?i)api[_-]?key['\"\\s]+[:=]+['\"\\s]+[A-Za-z0-9]{10,}")
        ]
        
        for (name, pattern) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(content.startIndex..., in: content)
                if regex.firstMatch(in: content, options: [], range: range) != nil {
                    found.append(name)
                }
            }
        }
        
        return found
    }
}