import AVFoundation
import Foundation
import Speech

/// Voice conversation state machine: capture → on-device transcription →
/// orchestrator → spoken response. Manual activation only; no wake word.
@MainActor
final class VoiceSession: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case listening
        case transcribing
        case processing
        case speaking
        case interrupted
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var liveTranscript: String = ""
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var permissionGranted = false

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let synthesizer = AVSpeechSynthesizer()
    private let settings: SettingsStore

    /// Called with the final transcript when listening ends.
    var onTranscript: ((String) -> Void)?
    /// Called when a state transitions to error.
    var onError: ((String) -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let micGranted: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micGranted else { return false }
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        permissionGranted = speechStatus == .authorized
        return permissionGranted
    }

    var speechRecognitionAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    var onDeviceRecognitionSupported: Bool {
        speechRecognizer?.supportsOnDeviceRecognition ?? false
    }

    // MARK: - Session control

    /// Toggle: idle → listening; listening → finish; speaking → interrupt.
    func toggle() {
        switch state {
        case .idle, .interrupted, .error:
            startListening()
        case .listening:
            finishListening()
        case .transcribing, .processing:
            cancelListening()
        case .speaking:
            interruptSpeaking()
        }
    }

    func startListening() {
        guard speechRecognitionAvailable else {
            fail("Speech recognition is not available on this Mac.")
            return
        }
        Task {
            if !permissionGranted {
                let granted = await requestPermissions()
                guard granted else {
                    fail("Microphone or speech recognition permission was denied.")
                    return
                }
            }
            beginCapture()
        }
    }

    private func beginCapture() {
        stopCapture()
        liveTranscript = ""

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            fail("Could not create a recognition request.")
            return
        }
        // On-device only — audio never leaves the Mac.
        if onDeviceRecognitionSupported {
            request.requiresOnDeviceRecognition = true
        }
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateLevel(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            fail("Could not start the microphone.")
            return
        }

        state = .listening

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.liveTranscript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finishListening()
                    }
                }
                if let error {
                    if case .listening = self.state {
                        self.fail(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func updateLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frames { sum += abs(channelData[i]) }
        let level = frames > 0 ? sum / Float(frames) : 0
        Task { @MainActor in self.audioLevel = min(1, level * 8) }
    }

    /// Stops capturing and delivers the transcript.
    func finishListening() {
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopCapture()
        guard !text.isEmpty else {
            state = .idle
            return
        }
        state = .transcribing
        onTranscript?(text)
    }

    func cancelListening() {
        stopCapture()
        liveTranscript = ""
        state = .idle
    }

    private func stopCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        audioLevel = 0
    }

    // MARK: - Orchestrator hooks

    func setProcessing() {
        if case .transcribing = state { state = .processing }
        else if case .listening = state { state = .processing }
    }

    /// Speak an assistant response (interruptible).
    func speak(_ text: String) {
        guard settings.speakResponses else {
            state = .idle
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        if !settings.voiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: settings.voiceIdentifier) {
            utterance.voice = voice
        }
        // Map 0...1 slider onto the system rate range.
        utterance.rate = AVSpeechUtteranceMinimumSpeechRate +
            (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate) * settings.speakingRate
        state = .speaking
        synthesizer.speak(utterance)
    }

    func interruptSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        state = .interrupted
    }

    private func fail(_ message: String) {
        stopCapture()
        state = .error(message)
        onError?(message)
    }
}

extension VoiceSession: @preconcurrency AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if case .speaking = self.state { self.state = .idle }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if case .speaking = self.state { self.state = .interrupted }
        }
    }
}
