import Testing
@testable import Tidewatch

struct LaunchModeTests {
    @Test func testHostEnvironmentMeansTests() {
        #expect(LaunchMode.current(arguments: ["Tidewatch"], environment: ["XCTestConfigurationFilePath": "/x"]) == .tests)
    }

    @Test func designPreviewTakesTheNextArgument() {
        #expect(LaunchMode.current(arguments: ["Tidewatch", "--design-preview", "Widget-Expanded"], environment: [:]) == .designPreview("widget-expanded"))
        #expect(LaunchMode.current(arguments: ["Tidewatch", "--design-preview"], environment: [:]) == .designPreview(""))
    }

    @Test func plainLaunchIsNormal() {
        #expect(LaunchMode.current(arguments: ["Tidewatch"], environment: [:]) == .normal)
    }
}
