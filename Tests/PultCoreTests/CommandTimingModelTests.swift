import Foundation
import Testing
@testable import PultCore

@Test
func processClockAgeIsNonNegativeAndAdvances() async throws {
    let first = ProcessClock.ageMilliseconds
    try await Task.sleep(for: .milliseconds(20))
    let second = ProcessClock.ageMilliseconds

    #expect(first >= 0)
    #expect(second >= first)
}
