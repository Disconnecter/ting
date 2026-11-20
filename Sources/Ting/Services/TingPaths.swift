// Where Ting keeps its data files, through BobukKit's `AppPaths`: `~/Library/Application Support/Ting/<name>`,
// or `<$TING_CONFIG>.<name>` next to an overridden config file, so manual checks and tests never
// read or change the real files and two overrides in one folder never share one.
import Foundation
import TingCore

extension AppPaths {
    static func ting(environment: [String: String] = ProcessInfo.processInfo.environment,
                     home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AppPaths {
        AppPaths(supportFolder: "Ting", configFolder: "ting", overrideVariable: "TING_CONFIG",
                 environment: environment, home: home)
    }
}
