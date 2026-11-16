import Darwin
import TingRuntime

@main
struct TingMicroMain {
    static func main() async {
        exit(await MicroAppCLI.main(Array(CommandLine.arguments.dropFirst())))
    }
}
