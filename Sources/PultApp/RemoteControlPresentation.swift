import Foundation
import SwiftUI
import PultCore

struct RemoteCommandFailure: Equatable, Identifiable {
    let id = UUID()
    var message: String
    var guidance: String

    init(message: String) {
        self.message = message
        self.guidance = Self.guidance(for: message)
    }

    private static func guidance(for message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("pair")
            || lowercased.contains("handshake")
            || lowercased.contains("tls") {
            return "Retry the command after reconnecting. If the handshake keeps failing, pair this TV again."
        }
        if lowercased.contains("reach")
            || lowercased.contains("timed out")
            || lowercased.contains("dns") {
            return "Wake the TV and retry. If discovery no longer shows it, add or update the TV with Manual IP."
        }
        if lowercased.contains("lost")
            || lowercased.contains("closed")
            || lowercased.contains("disconnect") {
            return "Reconnect the selected TV, then retry the command."
        }
        return "Retry the command, reconnect the selected TV, or pair again if the connection keeps failing."
    }
}

struct RemoteValidationPresentation {
    var title: String
    var detail: String
    var systemImage: String
    var tint: Color

    init(claimState: DeviceValidationClaimState) {
        switch claimState {
        case .unvalidated:
            title = "Validation not run"
            detail = "Run diagnostics on a physical TV."
            systemImage = "checklist"
            tint = .secondary
        case let .validated(validation):
            title = "Validated \(validation.validatedAt.formatted(date: .abbreviated, time: .omitted))"
            detail = "\(validation.passedAreas.count) passed areas"
            systemImage = "checkmark.seal.fill"
            tint = .green
        case let .needsAttention(report, lastSuccessful):
            title = lastSuccessful == nil ? "Validation needs attention" : "Revalidate needed"
            detail = report.summary
            systemImage = "exclamationmark.triangle.fill"
            tint = PultDesign.warning
        }
    }

    init(report: ValidationReport?) {
        guard let report else {
            title = "Validation not run"
            detail = "Run diagnostics on a physical TV."
            systemImage = "checklist"
            tint = .secondary
            return
        }

        if report.hasFailures {
            title = "Validation needs fixes"
            systemImage = "exclamationmark.triangle.fill"
            tint = PultDesign.warning
        } else if report.hasUnresolvedItems {
            title = "Validation needs review"
            systemImage = "questionmark.circle.fill"
            tint = PultDesign.warning
        } else if report.isSuccessfulPhysicalValidation {
            title = "Validated \(report.updatedAt.formatted(date: .abbreviated, time: .omitted))"
            systemImage = "checkmark.seal.fill"
            tint = .green
        } else {
            title = "Validation incomplete"
            systemImage = "checklist"
            tint = .secondary
        }
        detail = report.summary
    }
}
