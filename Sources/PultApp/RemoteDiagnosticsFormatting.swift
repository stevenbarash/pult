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
