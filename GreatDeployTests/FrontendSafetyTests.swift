import XCTest
import SwiftUI
@testable import GreatDeploy

final class FrontendSafetyTests: XCTestCase {
    
    @MainActor
    func testMainViewsInstantiateWithoutCrashing() {
        // Instantiate the views to ensure no structural or fatal runtime errors in initialization
        // This is the Swift equivalent of frontend syntax / structure checks
        
        let accountStore = AccountStore()
        
        // WelcomeView
        let welcomeView = WelcomeView()
            .environmentObject(accountStore)
        XCTAssertNotNil(welcomeView, "WelcomeView failed to instantiate")
        
        // AddEditAccountView
        let addEditAccountView = AddEditAccountView(mode: .add)
            .environmentObject(accountStore)
        XCTAssertNotNil(addEditAccountView, "AddEditAccountView failed to instantiate")
        
        // SettingsWindowView
        let settingsWindowView = SettingsWindowView()
            .environmentObject(accountStore)
        XCTAssertNotNil(settingsWindowView, "SettingsWindowView failed to instantiate")
        
        // GitHubCLISetupView
        let ghCLISetupView = GitHubCLISetupView()
        XCTAssertNotNil(ghCLISetupView, "GitHubCLISetupView failed to instantiate")
    }
}
