import Foundation
import PultCore

extension ConnectionState {
    var diagnosticText: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case let .failed(message):
            return "Failed: \(message)"
        }
    }
}

extension DiscoveryState {
    var diagnosticText: String {
        switch self {
        case .idle:
            return "Idle"
        case .scanning:
            return "Scanning"
        case .manualOnly:
            return "Manual IP recommended"
        case let .failed(message):
            return "Failed: \(message)"
        }
    }
}

extension DevicePresence {
    var diagnosticText: String {
        switch self {
        case .nearby:
            return "Found nearby"
        case .saved:
            return "Not found in latest scan"
        case .manual:
            return "Manual host"
        }
    }

    var managementText: String {
        switch self {
        case .nearby:
            return "Nearby"
        case .saved:
            return "Not nearby"
        case .manual:
            return "Manual"
        }
    }
}

extension DeviceReachability {
    var diagnosticText: String {
        switch self {
        case .unknown:
            return "Not checked"
        case .checking:
            return "Checking"
        case .reachable:
            return "Reachable"
        case let .unreachable(message, _):
            return "Unavailable: \(message)"
        }
    }

    var shortDiagnosticText: String {
        switch self {
        case .unknown:
            return "Not checked"
        case .checking:
            return "Checking"
        case .reachable:
            return "Reachable"
        case .unreachable:
            return "Unavailable"
        }
    }
}

extension RemoteVolumeStatus {
    var diagnosticText: String {
        "\(level)/\(maximum)\(muted ? " muted" : "")"
    }
}

extension RemoteProtocolCode {
    var diagnosticText: String {
        let labelsText = labels.isEmpty ? "no known features" : labels.joined(separator: ", ")
        return "\(rawValue) (\(labelsText))"
    }
}

extension RemoteDeviceInfo {
    var diagnosticText: String {
        var fields: [String] = []
        appendField("model", model, to: &fields)
        appendField("vendor", vendor, to: &fields)
        appendField("package", packageName, to: &fields)
        appendField("version", appVersion, to: &fields)
        if let unknown1 {
            fields.append("unknown1 \(unknown1)")
        }
        appendField("unknown2", unknown2, to: &fields)
        return fields.isEmpty ? "Observed without populated fields" : fields.joined(separator: ", ")
    }
}

extension RemoteAppInfo {
    var diagnosticText: String {
        var fields: [String] = []
        appendField("label", label, to: &fields)
        appendField("package", appPackage, to: &fields)
        if let counter {
            fields.append("counter \(counter)")
        }
        return fields.isEmpty ? "Observed without app fields" : fields.joined(separator: ", ")
    }
}

extension RemoteImeBatchEditObservation {
    var diagnosticText: String {
        var fields = ["\(edits.count) edit\(edits.count == 1 ? "" : "s")"]
        if let imeCounter {
            fields.append("ime counter \(imeCounter)")
        }
        if let fieldCounter {
            fields.append("field counter \(fieldCounter)")
        }
        if let status = derivedTextFieldStatus {
            fields.append("selection \(status.selectionStart)-\(status.selectionEnd)")
            let label = status.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty {
                fields.append("label \(label)")
            }
        }
        return fields.joined(separator: ", ")
    }
}

extension RemoteSessionProtocolState {
    var diagnosticLines: [String] {
        [
            "Configure from TV: \(negotiation.inboundConfigureCode?.value.diagnosticText ?? "Not observed this session")",
            "Configure response: \(negotiation.outboundConfigureCode?.value.diagnosticText ?? "Not sent this session")",
            "Set-active from TV: \(negotiation.inboundSetActiveDiagnosticText)",
            "Set-active response: \(negotiation.outboundSetActiveCode?.value.diagnosticText ?? "Not sent this session")",
            "Device info: \(deviceInfo?.value.diagnosticText ?? "Not observed this session")",
            "Remote start: \(remoteStart.map { "started=\($0.value)" } ?? "Not observed this session")",
            "IME app observation: \(imeApp?.value.diagnosticText ?? "Not observed this session")",
            "Last IME batch: \(lastImeBatchEdit?.value.diagnosticText ?? "Not observed this session")"
        ]
    }
}

private extension RemoteProtocolNegotiation {
    var inboundSetActiveDiagnosticText: String {
        guard let observation = inboundSetActiveCode else {
            return "Not observed this session"
        }
        return observation.value?.diagnosticText ?? "Observed without active field"
    }
}

private func appendField(_ label: String, _ value: String?, to fields: inout [String]) {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return
    }
    fields.append("\(label) \(value)")
}
