import Foundation
import SwiftUI
import PultCore
#if os(iOS) && canImport(AVFoundation)
import AVFoundation
#endif

struct VoiceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: RemoteControlModel
    @State private var controller = VoiceSearchController()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 12)

                Image(systemName: controller.isRecording ? "mic.circle.fill" : "mic.circle")
                    .font(.system(size: 82, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(controller.isRecording ? PultDesign.accent : PultDesign.utility)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(controller.title)
                        .font(PultTypography.displaySmall)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Text(controller.detail)
                        .font(PultTypography.bodySmall)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.86)
                }
                .accessibilityElement(children: .combine)

                if let errorMessage = controller.errorMessage {
                    Text(errorMessage)
                        .font(PultTypography.bodySmall.weight(.semibold))
                        .foregroundStyle(PultDesign.warning)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.84)
                }

                Button {
                    Task { @MainActor in
                        if controller.isRecording {
                            await controller.stop()
                            dismiss()
                        } else {
                            await controller.start(model: model)
                        }
                    }
                } label: {
                    Label(controller.isRecording ? "Stop" : "Start", systemImage: controller.isRecording ? "stop.fill" : "mic.fill")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.isRecording ? PultDesign.danger : PultDesign.accent)
                .disabled(controller.isStarting)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { RemoteBackground() }
            .navigationTitle("Voice Search")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        Task { @MainActor in
                            await controller.stop()
                            dismiss()
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await controller.start(model: model)
        }
        .onDisappear {
            Task { @MainActor in
                await controller.stop()
            }
        }
    }
}

@MainActor
@Observable
private final class VoiceSearchController {
    var isStarting = false
    var isRecording = false
    var errorMessage: String?

    private var model: RemoteControlModel?
    private var sessionID: Int?
    private var pendingSamples = Data()

    #if os(iOS) && canImport(AVFoundation)
    private var engine: AVAudioEngine?
    #endif

    private static let minimumChunkBytes = 8 * 1024
    private static let maximumChunkBytes = 20 * 1024

    var title: String {
        if isRecording {
            return "Listening"
        }
        if isStarting {
            return "Starting"
        }
        return "Voice Search"
    }

    var detail: String {
        if isRecording {
            return "Audio is streaming to the selected TV."
        }
        if isStarting {
            return "Opening voice search on the TV."
        }
        return "Start a TV voice session from this iPhone."
    }

    func start(model: RemoteControlModel) async {
        guard !isStarting, !isRecording else { return }
        self.model = model
        errorMessage = nil
        isStarting = true

        #if os(iOS) && canImport(AVFoundation)
        guard await requestMicrophoneAccess() else {
            fail("Microphone access is off for Pult.")
            return
        }
        guard isStarting else { return }

        await model.ensureConnected(staleAfter: 30)
        guard isStarting else { return }
        guard model.session.connectionState == .connected else {
            fail(model.session.lastError ?? "Connect to the TV before voice search.")
            return
        }

        let startResult = await model.session.startVoiceSession()
        guard isStarting else {
            if case let .started(sessionID) = startResult {
                await model.session.endVoiceSession(sessionID: sessionID)
            }
            return
        }

        switch startResult {
        case let .started(sessionID):
            self.sessionID = sessionID
            do {
                try startAudioEngine()
                isRecording = true
                isStarting = false
            } catch {
                await model.session.endVoiceSession(sessionID: sessionID)
                fail("Could not start the microphone: \(error.localizedDescription)")
            }
        case let .failed(message):
            fail(message)
        }
        #else
        fail("Voice search requires iPhone microphone support.")
        #endif
    }

    func stop() async {
        guard isRecording || isStarting || sessionID != nil else { return }
        isStarting = false
        isRecording = false

        #if os(iOS) && canImport(AVFoundation)
        stopAudioEngine()
        #endif

        if let sessionID, let model {
            await flushSamples(padToMinimum: true)
            await model.session.endVoiceSession(sessionID: sessionID)
        }
        sessionID = nil
        pendingSamples.removeAll(keepingCapacity: false)
    }

    private func fail(_ message: String) {
        errorMessage = message
        isStarting = false
        isRecording = false
        sessionID = nil
        pendingSamples.removeAll(keepingCapacity: false)
    }

    private func enqueueSamples(_ samples: Data) async {
        guard isRecording, sessionID != nil else { return }
        pendingSamples.append(samples)
        await flushSamples(padToMinimum: false)
    }

    private func flushSamples(padToMinimum: Bool) async {
        guard let sessionID, let model else { return }

        while pendingSamples.count >= Self.minimumChunkBytes {
            let chunkSize = min(Self.maximumChunkBytes, pendingSamples.count)
            let chunk = Data(pendingSamples.prefix(chunkSize))
            pendingSamples.removeFirst(chunkSize)
            _ = await model.session.sendVoiceSamples(chunk, sessionID: sessionID)
        }

        if padToMinimum, !pendingSamples.isEmpty {
            if pendingSamples.count < Self.minimumChunkBytes {
                pendingSamples.append(Data(repeating: 0, count: Self.minimumChunkBytes - pendingSamples.count))
            }
            let chunk = pendingSamples
            pendingSamples.removeAll(keepingCapacity: false)
            _ = await model.session.sendVoiceSamples(chunk, sessionID: sessionID)
        }
    }

    #if os(iOS) && canImport(AVFoundation)
    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        }
    }

    private func startAudioEngine() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setPreferredSampleRate(8_000)
        try audioSession.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        if #available(iOS 27.0, *) {
            try inputNode.installAudioTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                let mutableBuffer = AVAudioPCMBuffer(copying: buffer)
                let samples = Self.pcm16Mono8kSamples(from: mutableBuffer, inputFormat: inputFormat)
                guard !samples.isEmpty else { return }
                Task { @MainActor [weak self] in
                    await self?.enqueueSamples(samples)
                }
            }
        } else {
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                let samples = Self.pcm16Mono8kSamples(from: buffer, inputFormat: inputFormat)
                guard !samples.isEmpty else { return }
                Task { @MainActor [weak self] in
                    await self?.enqueueSamples(samples)
                }
            }
        }

        try engine.start()
        self.engine = engine
    }

    private func stopAudioEngine() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    nonisolated private static func pcm16Mono8kSamples(from buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) -> Data {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else {
            return Data()
        }

        let sourceRate = inputFormat.sampleRate
        guard sourceRate > 0 else { return Data() }

        let sourceFrames = Int(buffer.frameLength)
        let outputFrames = max(1, Int(Double(sourceFrames) * 8_000.0 / sourceRate))
        var data = Data()
        data.reserveCapacity(outputFrames * MemoryLayout<Int16>.size)

        let channel = channels[0]
        for outputIndex in 0..<outputFrames {
            let sourceIndex = min(Int(Double(outputIndex) * sourceRate / 8_000.0), sourceFrames - 1)
            let sample = max(-1, min(1, channel[sourceIndex]))
            var pcm = Int16(sample * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &pcm) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        return data
    }
    #endif
}
