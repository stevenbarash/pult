import Foundation

extension Duration {
    /// This duration as a floating-point count of milliseconds.
    var millisecondsValue: Double {
        let c = components
        return Double(c.seconds) * 1_000 + Double(c.attoseconds) / 1_000_000_000_000_000
    }
}

/// One Lock Screen / headless command's connect-and-send timing, captured by
/// the measurement pass. Pure data: written to the shared timing log and read
/// back by the in-app Diagnostics readout. Measurement only — it never gates or
/// changes command behavior.
public struct CommandTiming: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    /// RemoteKey raw value, e.g. "volumeUp", or "appLink".
    public let key: String
    /// Wall-clock start, used only for display ordering.
    public let startedAt: Date
    /// Entry-to-sent wall time in milliseconds.
    public let totalMs: Double
    /// True when the command had to dial the TV (COLD); false when it reused a
    /// live socket (WARM).
    public let dialed: Bool
    /// TCP + mutual-TLS handshake time, present only when `dialed`.
    public let tcpTlsMs: Double?
    /// Protocol `configure` handshake time, present only when `dialed`.
    public let configureMs: Double?
    /// Milliseconds since this process first touched the remote stack — a
    /// fresh-launch heuristic, not an exact process age.
    public let processAgeMs: Double
    /// Whether the command was delivered.
    public let succeeded: Bool

    public init(
        id: UUID = UUID(),
        key: String,
        startedAt: Date,
        totalMs: Double,
        dialed: Bool,
        tcpTlsMs: Double?,
        configureMs: Double?,
        processAgeMs: Double,
        succeeded: Bool
    ) {
        self.id = id
        self.key = key
        self.startedAt = startedAt
        self.totalMs = totalMs
        self.dialed = dialed
        self.tcpTlsMs = tcpTlsMs
        self.configureMs = configureMs
        self.processAgeMs = processAgeMs
        self.succeeded = succeeded
    }

    /// "WARM" or "COLD".
    public var classification: String { dialed ? "COLD" : "WARM" }

    /// Heuristic: the command arrived so soon after the process first touched
    /// the remote stack that the process was likely cold-launched for it.
    public var likelyFreshLaunch: Bool { processAgeMs < 1_500 }

    /// Milliseconds spent sending, derived as the remainder after the dial
    /// phases. Approximate (it also absorbs decision overhead).
    public var sendMsApprox: Double {
        max(totalMs - (tcpTlsMs ?? 0) - (configureMs ?? 0), 0)
    }

    private static func formatMs(_ value: Double) -> String {
        value >= 1_000
            ? String(format: "%.1f s", value / 1_000)
            : "\(Int(value.rounded())) ms"
    }

    /// e.g. "volumeUp  COLD  312 ms".
    public var summaryLine: String {
        "\(key)  \(classification)  \(Self.formatMs(totalMs))"
    }

    /// e.g. "tcp+tls 181 · configure 121 · send ~10" or "reused socket · send ~14".
    public var detailLine: String {
        if dialed {
            let tcp = Int((tcpTlsMs ?? 0).rounded())
            let cfg = Int((configureMs ?? 0).rounded())
            let send = Int(sendMsApprox.rounded())
            let launch = likelyFreshLaunch ? " · fresh launch" : ""
            return "tcp+tls \(tcp) · configure \(cfg) · send ~\(send)\(launch)"
        } else {
            return "reused socket · send ~\(Int(sendMsApprox.rounded()))"
        }
    }
}
