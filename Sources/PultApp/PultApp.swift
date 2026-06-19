import SwiftUI
import PultCore
import os

#if canImport(MetricKit)
import MetricKit
#endif

#if canImport(PostHog)
import PostHog
#endif

@main
struct PultApp: App {
    // The same instance intents resolve via SharedRemote, so a command sent
    // from the Lock Screen and the on-screen remote drive one session.
    private let model = SharedRemote.model

    init() {
        _ = ProcessClock.start
        AppObservability.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            RemoteRootView(model: model)
                // Applied above the root so sheets, which inherit their
                // environment from inside RemoteRootView, pick it up too.
                .tint(.pultAccent)
        }
    }
}

private enum AppObservability {
    private static let logger = Logger(subsystem: "app.pult", category: "app-lifecycle")

#if canImport(MetricKit)
    private static let metricSubscriber = PultMetricKitSubscriber()
#endif

    static func bootstrap() {
        logger.info("action=launch outcome=started duration_ms=-")
        configureMetricKit()
        configurePostHogIfAvailable()
    }

    private static func configureMetricKit() {
#if canImport(MetricKit)
        MXMetricManager.shared.add(metricSubscriber)
        logger.info("action=metrickit outcome=succeeded duration_ms=-")
#else
        logger.info("action=metrickit outcome=unavailable duration_ms=-")
#endif
    }

    private static func configurePostHogIfAvailable() {
#if canImport(PostHog)
        guard let projectToken = Bundle.main.object(forInfoDictionaryKey: "PultPostHogProjectToken") as? String,
              !projectToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.info("action=posthog outcome=skipped duration_ms=- reason=missing_project_token")
            return
        }

        let config = PostHogConfig(
            projectToken: projectToken,
            host: postHogHost()
        )
        config.captureApplicationLifecycleEvents = true
        PostHogSDK.shared.setup(config)
        logger.info("action=posthog outcome=succeeded duration_ms=-")
#else
        logger.info("action=posthog outcome=unavailable duration_ms=- reason=sdk_not_linked")
#endif
    }

    private static func postHogHost(from bundle: Bundle = .main) -> String {
        if let host = (bundle.object(forInfoDictionaryKey: "PultPostHogHost") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty {
            return host
        }
        return "https://us.i.posthog.com"
    }
}

#if canImport(MetricKit)
private final class PultMetricKitSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private let logger = Logger(subsystem: "app.pult", category: "metrics")

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            logger.info(
                "action=metric_payload outcome=succeeded duration_ms=- payload_bytes=\(payload.jsonRepresentation().count, privacy: .public)"
            )
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            logger.error(
                "action=diagnostic_payload outcome=succeeded duration_ms=- payload_bytes=\(payload.jsonRepresentation().count, privacy: .public)"
            )
        }
    }
}
#endif
