import XCTest
@testable import GreatDeploy

final class ValidationUtilitiesTests: XCTestCase {

    func testIsValidEmail() {
        XCTAssertTrue(ValidationUtilities.isValidEmail("user@example.com"))
        XCTAssertTrue(ValidationUtilities.isValidEmail("user.name+tag@domain.co.uk"))
        
        XCTAssertFalse(ValidationUtilities.isValidEmail("invalid-email"))
        XCTAssertFalse(ValidationUtilities.isValidEmail("user@"))
        XCTAssertFalse(ValidationUtilities.isValidEmail("@domain.com"))
    }

    func testIsValidGitHubUsername() {
        XCTAssertTrue(ValidationUtilities.isValidGitHubUsername("valid-username"))
        XCTAssertTrue(ValidationUtilities.isValidGitHubUsername("ValidUser123"))
        
        XCTAssertFalse(ValidationUtilities.isValidGitHubUsername("-invalid"))
        XCTAssertFalse(ValidationUtilities.isValidGitHubUsername("invalid-"))
        XCTAssertFalse(ValidationUtilities.isValidGitHubUsername("invalid--username"))
        XCTAssertFalse(ValidationUtilities.isValidGitHubUsername("username_with_underscore"))
    }
}
