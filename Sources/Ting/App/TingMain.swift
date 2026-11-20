// The entry point: command-line modes first, then the menu-bar app.
import BobukUpdates
import Foundation
import TingCore

@main
enum TingMain {
    static func main() {
        // Only the progress window of a Homebrew update, from the copy in its run folder; never returns.
        MainActor.assumeIsolated {
            HomebrewLaunch.runViewerIfRequested(app: .ting, palette: TingPickerStyle.palette)
        }
        // The update helper restarts Ting with its own arguments: they are not a command line.
        let arguments = HomebrewLaunch.isUpdateLaunch() ? [] : Array(CommandLine.arguments.dropFirst())
        if MicroAppCheckCommand.handles(arguments) {
            // Before the app starts: no window, no menu-bar icon, no config read, no file written.
            exit(runCheck(arguments))
        }
        if AgentPrompt.handles(arguments) {
            // The same rules as --check: nothing starts, nothing is read but the bundle, nothing is written.
            print(AgentPromptSource.text())
            exit(0)
        }
        TingApp.main()
    }

    /// Reads the given files, prints the result and returns the exit code.
    static func runCheck(_ arguments: [String]) -> Int32 {
        let outcome = MicroAppCheckCommand.run(arguments, read: { path in
            try Data(contentsOf: URL(fileURLWithPath: path))
        }, libraries: { MicroAppLibraries.read(folder: MicroAppCheckCommand.libraryFolder(for: $0)) })
        for line in outcome.output { print(line) }
        if !outcome.errors.isEmpty {
            FileHandle.standardError.write(Data(outcome.errors.map { $0 + "\n" }.joined().utf8))
        }
        return outcome.exitCode
    }
}
