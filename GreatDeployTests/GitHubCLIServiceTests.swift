import XCTest
@testable import GreatDeploy

final class GitHubCLIServiceTests: XCTestCase {

    func testParseAuthStatusUsernamesPreservesCasing() {
        let output = """
        github.com
          ✓ Logged in to github.com account MinhOmega (keyring)
          ✓ Logged in to github.com account work-user (keyring)
        """

        XCTAssertEqual(
            GitHubCLIService.parseAuthStatusUsernames(from: output),
            ["MinhOmega", "work-user"]
        )
    }

    func testFindCorrectCaseUsernameMatchesCaseInsensitively() {
        let output = "✓ Logged in to github.com account MinhOmega (keyring)"

        XCTAssertEqual(
            GitHubCLIService.findCorrectCaseUsername("minhomega", in: output),
            "MinhOmega"
        )
    }
}

