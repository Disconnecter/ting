// The entry point: command-line modes first, then the menu-bar app.
import Foundation
import TingCore

@main
enum TingMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if MicroAppCheckCommand.handles(arguments) {
            // Before the app starts: no window, no menu-bar icon, no config read, no file written.
            exit(runCheck(arguments))
        }
        TingApp.main()
    }

    /// Reads the given files, prints the result and returns the exit code.
    static func runCheck(_ arguments: [String]) -> Int32 {
        let outcome = MicroAppCheckCommand.run(arguments) { path in
            try Data(contentsOf: URL(fileURLWithPath: path))
        }
        for line in outcome.output { print(line) }
        if !outcome.errors.isEmpty {
            FileHandle.standardError.write(Data(outcome.errors.map { $0 + "\n" }.joined().utf8))
        }
        return outcome.exitCode
    }
}
