import Foundation
import Testing
@testable import PultCore

@Test
func coldTimingSummaryAndDetailFormatWithPhases() {
    let timing = CommandTiming(
        key: "volumeUp",
        startedAt: Date(timeIntervalSince1970: 1_000),
        totalMs: 312,
        dialed: true,
        tcpTlsMs: 181,
        configureMs: 121,
        processAgeMs: 5_000,
        succeeded: true
    )

    #expect(timing.classification == "COLD")
    #expect(timing.summaryLine == "volumeUp  COLD  312 ms")
    #expect(timing.detailLine == "tcp+tls 181 · configure 121 · send ~10")
    #expect(timing.likelyFreshLaunch == false)
}

@Test
func warmTimingReportsReusedSocketAndFreshLaunchHeuristic() {
    let timing = CommandTiming(
        key: "home",
        startedAt: Date(timeIntervalSince1970: 2_000),
        totalMs: 1_400,
        dialed: true,
        tcpTlsMs: 410,
        configureMs: 690,
        processAgeMs: 800,
        succeeded: true
    )
    #expect(timing.summaryLine == "home  COLD  1.4 s")
    #expect(timing.likelyFreshLaunch == true)

    let warm = CommandTiming(
        key: "mute",
        startedAt: Date(timeIntervalSince1970: 3_000),
        totalMs: 14,
        dialed: false,
        tcpTlsMs: nil,
        configureMs: nil,
        processAgeMs: 60_000,
        succeeded: true
    )
    #expect(warm.classification == "WARM")
    #expect(warm.detailLine == "reused socket · send ~14")
}

@Test
func durationMillisecondsValueConvertsSecondsAndFraction() {
    #expect(Duration.milliseconds(250).millisecondsValue == 250)
    #expect(Duration.seconds(2).millisecondsValue == 2_000)
}
