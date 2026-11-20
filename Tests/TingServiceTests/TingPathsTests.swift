import Foundation
import XCTest
import TingCore
@testable import Ting

/// The data files moved onto BobukKit's `AppPaths.dataFile`: the URLs must be byte-identical to
/// the rule each store had, `<$TING_CONFIG>.<name>` or `~/Library/Application Support/Ting/<name>`.
final class TingPathsTests: XCTestCase {
    private func legacy(_ name: String, environment: [String: String], home: URL) -> URL {
        if let config = environment["TING_CONFIG"], !config.isEmpty {
            return URL(fileURLWithPath: (config as NSString).expandingTildeInPath).appendingPathExtension(name)
        }
        return home.appendingPathComponent("Library/Application Support/Ting/\(name)")
    }

    func testDataFilesAreByteIdenticalToTheOldRule() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let environments: [[String: String]] = [
            [:],
            ["TING_CONFIG": ""],
            ["TING_CONFIG": "/tmp/ting-test.json"],
            ["TING_CONFIG": "/tmp/x/config.json"],
            ["TING_CONFIG": "~/ting/config.json"],
            ["TING_CONFIG": "/tmp/a b/../c/./config.json"],
            ["TING_CONFIG": "/private/tmp/Ting Folder/my config.json"],
        ]
        let stores: [(String, ([String: String], URL) -> URL)] = [
            ("launcha-history.json", { LaunchaHistoryStore.defaultURL(environment: $0, home: $1) }),
            ("launcha-consent.json", { LaunchaConsentStore.defaultURL(environment: $0, home: $1) }),
            ("micro-values.json", { MicroAppValueStore.defaultURL(environment: $0, home: $1) }),
            ("micro-approvals.json", { MicroAppApprovalStore.defaultURL(environment: $0, home: $1) }),
            ("micro-link-notice.json", { MicroAppLinkNoticeStore.defaultURL(environment: $0, home: $1) }),
        ]
        for environment in environments {
            for (name, url) in stores {
                let old = legacy(name, environment: environment, home: home)
                let new = url(environment, home)
                XCTAssertEqual(new, old, "\(name) \(environment)")
                XCTAssertEqual(new.path, old.path, "\(name) \(environment)")
                XCTAssertEqual(new.absoluteString, old.absoluteString, "\(name) \(environment)")
            }
        }
    }
}
