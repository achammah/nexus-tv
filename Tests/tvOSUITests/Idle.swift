import XCTest

/// Waits while the test runner keeps its run loop turning (a blocking sleep() trips the scene watchdog after 10 s).
func idle(_ seconds: Double) {
    guard seconds > 0 else { return }
    _ = XCTWaiter.wait(for: [XCTestExpectation(description: "idle")], timeout: seconds)
}
