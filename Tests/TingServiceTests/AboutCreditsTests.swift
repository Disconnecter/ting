import AppKit
import XCTest
import TingCore
@testable import Ting

@MainActor
final class AboutCreditsTests: XCTestCase {
    /// Every contributor appears in About Ting, with their name linked to their GitHub profile.
    func testCreditsListEveryContributorWithAProfileLink() {
        let credits = AboutCredits.text()
        XCTAssertTrue(credits.string.hasPrefix("Contributors\n"))
        var links: [URL] = []
        credits.enumerateAttribute(.link, in: NSRange(location: 0, length: credits.length)) { value, range, _ in
            guard let url = value as? URL else { return }
            links.append(url)
            XCTAssertEqual((credits.string as NSString).substring(with: range),
                           Contributors.all.first { $0.profileURL == url }?.name)
        }
        XCTAssertEqual(links, Contributors.all.map(\.profileURL))
        for person in Contributors.all { XCTAssertTrue(credits.string.contains(person.contributions)) }
    }
}
