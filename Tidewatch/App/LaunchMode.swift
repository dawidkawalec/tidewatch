import Foundation

/// How the process was started. Tests and the design preview never touch the real data folder,
/// the real settings.json or the real widget.
enum LaunchMode: Equatable {
    case normal
    case designPreview(String)
    case tests

    static func current(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LaunchMode {
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
            return .tests
        }
        if let index = arguments.firstIndex(of: "--design-preview") {
            let next = arguments.index(after: index)
            return .designPreview(next < arguments.endIndex ? arguments[next].lowercased() : "")
        }
        return .normal
    }
}
