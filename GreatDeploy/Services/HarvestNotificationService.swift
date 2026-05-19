import Foundation
import UserNotifications
import os.log

final class HarvestNotificationService: HarvestNotificationServicing {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GreatDeploy", category: "Notification")
    static let shared = HarvestNotificationService()
    
    private let center = UNUserNotificationCenter.current()
    private let categoryIdentifier = "GREATDEPLOY_SKILLS"
    private let reviewActionIdentifier = "REVIEW_SKILLS"
    
    private init() {
        setupCategory()
    }
    
    private func setupCategory() {
        let reviewAction = UNNotificationAction(
            identifier: reviewActionIdentifier,
            title: "Review Skills",
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Later",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [reviewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            Self.logger.info("Notification authorization: \(granted ? "granted" : "denied")")
            return granted
        } catch {
            Self.logger.error("Notification authorization failed: \(error.localizedDescription)")
            return false
        }
    }
    
    func sendDiscoveryNotification(skillCount: Int, toolCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Skills Discovered"
        content.body = "Found \(skillCount) skills from \(toolCount) AI tools. Tap to review."
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "skill-discovery-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        center.add(request) { error in
            if let error = error {
                Self.logger.error("Failed to schedule notification: \(error.localizedDescription)")
            } else {
                Self.logger.info("Discovery notification scheduled")
            }
        }
    }
    
    func sendConflictNotification(skillName: String, sourceTool: String) {
        let content = UNMutableNotificationContent()
        content.title = "Skill Conflict Detected"
        content.body = "\(skillName) from \(sourceTool) conflicts with existing skill. Tap to resolve."
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "skill-conflict-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        center.add(request) { error in
            if let error = error {
                Self.logger.error("Failed to schedule conflict notification: \(error.localizedDescription)")
            }
        }
    }
}