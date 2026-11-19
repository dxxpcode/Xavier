import AVFoundation
import Foundation
import Speech

/// Voice conversation state machine: capture → on-device transcription →
/// orchestrator → spoken response. Supports always-on "Hey Xavier" wake word
/// and a conversational follow-up window after each spoken reply.
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
    /// True while the recognizer is passively listening for "Hey Xavier".
    @Published private(set) var wakeWordActive = false

    private let audioEngine = AVAudioEngine()
    private var tapInstalled = false
    private var awaitingFinalResult = false
    private var finishGeneration = 0
    nonisolated(unsafe) private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let synthesizer = AVSpeechSynthesizer()
    private let settings: SettingsStore

    /// Called with the final transcript and the conversation that was active
    /// when listening began.
    var onTranscript: ((String, String?) -> Void)?
    /// Returns the conversation voice input should target; set by AppState.
    var conversationProvider: (() -> String?)?
    private var targetConversationID: String?
    /// Called when the wake word is detected; AppDelegate shows the panel.
    var onWakeWord: (() -> Void)?
    /// Called when a state transitions to error.
    var onError: ((String) -> Void)?

    // MARK: - Wake word

    nonisolated(unsafe) private var wakeWordRequest: SFSpeechAudioBufferRecognitionRequest?
    private var wakeWordTask: SFSpeechRecognitionTask?
    /// Guards the two request references the audio tap reads off-actor.
    private let requestLock = NSLock()
    private var wakeRestartTask: Task<Void, Never>?
    /// Incremented whenever wake mode is (re)armed or torn down, so a stale
    /// result handler can't activate or cancel a newer task.
    private var wakeGeneration = 0
    private var wakeRestartAttempts = 0

    // MARK: - Follow-up

    private var followUpPending = false
    private var followUpTimeoutTask: Task<Void, Never>?
    /// Last time a partial transcript arrived; detects "user is still speaking".
    private var lastPartialAt = Date.distantPast
    /// Command text captured alongside the wake phrase, seeded into the new capture.
    private var wakeCommandSeed: String?
    /// The seeded command with a trailing space, prepended to every new
    /// recognition result so the opening words aren't lost.
    private var captureSeedPrefix = ""
    /// Conversation the last delivered transcript (and its reply) belonged to;
    /// set by AppState so follow-ups stay in the same chat.
    var lastExchangeConversationID: String?

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
        if permissionGranted { applyVoiceSettings() }
        return permissionGranted
    }

    /// Synchronously refresh the cached permission flag (no prompts).
    func refreshPermissionStatus() {
        permissionGranted = AVAudioApplication.shared.recordPermission == .granted
            && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    var speechRecognitionAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    var onDeviceRecognitionSupported: Bool {
        speechRecognizer?.supportsOnDeviceRecognition ?? false
    }

    // MARK: - Session control

    /// Apply current settings: start or stop the wake-word loop. Called at
    /// launch and whenever voice preferences change.
    func applyVoiceSettings() {
        if settings.wakeWordEnabled {
            maybeStartWakeListening()
        } else {
            stopWakeListening()
        }
        if !settings.voiceFollowUpEnabled && followUpPending {
            cancelListening()
        }
    }

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
        stopWakeTask()
        stopCapture()
        liveTranscript = wakeCommandSeed ?? ""
        captureSeedPrefix = wakeCommandSeed.map { $0 + " " } ?? ""
        wakeCommandSeed = nil

        // On-device only — audio never leaves the Mac.
        guard onDeviceRecognitionSupported else {
            fail("On-device speech recognition is not supported on this Mac.")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            fail("Could not create a recognition request.")
            return
        }
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true

        guard installTapIfNeeded() else {
            recognitionRequest = nil
            fail("No usable microphone input is available.")
            return
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            fail("Could not start the microphone.")
            return
        }

        state = .listening
        targetConversationID = followUpPending ? lastExchangeConversationID : conversationProvider?()

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.liveTranscript = self.captureSeedPrefix + result.bestTranscription.formattedString
                    if !result.isFinal { self.lastPartialAt = Date() }
                    if result.isFinal {
                        if self.awaitingFinalResult {
                            self.deliverTranscript()
                        } else {
                            self.finishListening()
                        }
                    }
                }
                if let error {
                    if self.awaitingFinalResult {
                        self.deliverTranscript()
                    } else if case .listening = self.state {
                        self.fail(error.localizedDescription)
                    }
                }
            }
        }
    }

    /// One tap feeds both the dictation request and the wake-word request.
    /// Returns false when the input node reports no usable format (e.g. no mic).
    private func installTapIfNeeded() -> Bool {
        guard !tapInstalled else { return true }
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.requestLock.lock()
            let request = self.recognitionRequest
            let wakeRequest = self.wakeWordRequest
            self.requestLock.unlock()
            request?.append(buffer)
            wakeRequest?.append(buffer)
            self.updateLevel(buffer)
        }
        tapInstalled = true
        return true
    }

    private func updateLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frames { sum += abs(channelData[i]) }
        let level = frames > 0 ? sum / Float(frames) : 0
        Task { @MainActor in self.audioLevel = min(1, level * 8) }
    }

    /// Stops capturing audio and lets the recognizer finish buffered audio;
    /// the final result (or a 2s-timeout fallback) is delivered to onTranscript.
    func finishListening() {
        guard case .listening = state else { return }
        state = .transcribing
        awaitingFinalResult = true
        let generation = finishGeneration
        stopAudioInput()
        // Fallback: if no final result arrives, submit the last partial text.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.awaitingFinalResult, self.finishGeneration == generation else { return }
            self.deliverTranscript()
        }
    }

    private func deliverTranscript() {
        awaitingFinalResult = false
        followUpPending = false
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        recognitionTask = nil
        followUpTimeoutTask?.cancel()
        guard !text.isEmpty else {
            enterStandby()
            return
        }
        // In a follow-up turn, a phrase that is just the wake word is a
        // stray recognition, not a command.
        if normalizedWakeText(text) == "xavier" {
            enterStandby()
            return
        }
        onTranscript?(text, targetConversationID)
    }

    func cancelListening() {
        awaitingFinalResult = false
        followUpPending = false
        followUpTimeoutTask?.cancel()
        stopCapture()
        liveTranscript = ""
        enterStandby()
    }

    /// Stops the engine and tap, ending the audio feed but letting the
    /// recognizer deliver its final result.
    private func stopAudioInput() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        recognitionRequest?.endAudio()
        requestLock.lock()
        recognitionRequest = nil
        requestLock.unlock()
        audioLevel = 0
    }

    private func stopCapture() {
        awaitingFinalResult = false
        finishGeneration += 1
        stopAudioInput()
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    /// Return to a passive state; resumes the wake-word loop when enabled.
    private func enterStandby() {
        if case .speaking = state { return }
        state = .idle
        maybeStartWakeListening()
    }

    // MARK: - Wake word loop

    private var wakeDesired: Bool {
        settings.wakeWordEnabled && permissionGranted && onDeviceRecognitionSupported
    }

    /// Start passive "Hey Xavier" listening when the session is at rest.
    private func maybeStartWakeListening() {
        guard wakeDesired, wakeWordTask == nil, recognitionRequest == nil else { return }
        switch state {
        case .idle, .interrupted, .error:
            break
        default:
            return
        }
        guard installTapIfNeeded() else {
            scheduleWakeRestart()
            return
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            scheduleWakeRestart()
            return
        }
        startWakeTask()
    }

    private func startWakeTask() {
        wakeGeneration += 1
        let generation = wakeGeneration
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        requestLock.lock()
        wakeWordRequest = request
        requestLock.unlock()
        wakeWordActive = true
        wakeWordTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                guard self.wakeGeneration == generation else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if self.matchesWakeWord(text) {
                        switch self.state {
                        case .idle, .interrupted, .error:
                            // Only react at rest — never mid-capture or while
                            // speaking, which would feed back on our own voice.
                            self.handleWakeWord(from: text)
                            return
                        default:
                            break
                        }
                    }
                    // Recognition tasks cap out around a minute of audio; a
                    // final result without a match means it's time to re-arm.
                    if result.isFinal { self.scheduleWakeRestart() }
                } else if error != nil {
                    self.scheduleWakeRestart()
                }
            }
        }
    }

    private func normalizedWakeText(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func matchesWakeWord(_ text: String) -> Bool {
        let normalized = normalizedWakeText(text)
        return normalized.contains("hey xavier") || normalized.contains("a xavier")
    }

    private func handleWakeWord(from text: String) {
        wakeWordActive = false
        wakeRestartAttempts = 0
        // "Hey Xavier, <command>" — keep the command for the new capture.
        wakeCommandSeed = commandAfterWakePhrase(in: text)
        onWakeWord?()
        startListening()
    }

    /// Text after the wake phrase in the raw transcript, preserving
    /// punctuation (normalized text would mangle values like "3.5").
    private func commandAfterWakePhrase(in text: String) -> String? {
        let lower = text.lowercased()
        var searchStart = lower.startIndex
        // Scan every occurrence — an earlier "Xavier" not preceded by hey/a
        // isn't the wake phrase (e.g. "tell Xavier: hey Xavier, open notes").
        while let xavier = lower.range(of: "xavier", range: searchStart..<lower.endIndex) {
            // "Xavier's" is possessive, not the wake phrase — keep scanning.
            if lower[xavier.upperBound...].first == "'" {
                searchStart = xavier.upperBound
                continue
            }
            let before = normalizedWakeText(String(lower[..<xavier.lowerBound]))
            if before == "hey" || before == "a" || before.hasSuffix(" hey") || before.hasSuffix(" a") {
                let rest = String(text[xavier.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?"))
                return rest.isEmpty ? nil : rest
            }
            searchStart = xavier.upperBound
        }
        return nil
    }

    /// Restart the wake task after the recognizer's per-task audio limit or a
    /// transient failure, with light backoff so persistent errors don't spin.
    private func scheduleWakeRestart() {
        wakeWordTask?.cancel()
        wakeWordTask = nil
        requestLock.lock()
        wakeWordRequest = nil
        requestLock.unlock()
        wakeWordActive = false
        guard wakeDesired, wakeRestartTask == nil else { return }
        wakeRestartAttempts += 1
        let delay = min(0.5 * Double(wakeRestartAttempts), 5)
        wakeRestartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            self.wakeRestartTask = nil
            self.maybeStartWakeListening()
        }
    }

    /// Cancel only the wake task/request; leaves engine state to the caller.
    private func stopWakeTask() {
        wakeGeneration += 1
        wakeRestartTask?.cancel()
        wakeRestartTask = nil
        wakeWordTask?.cancel()
        wakeWordTask = nil
        requestLock.lock()
        wakeWordRequest = nil
        requestLock.unlock()
        wakeWordActive = false
        wakeRestartAttempts = 0
    }

    private func stopWakeListening() {
        stopWakeTask()
        if case .idle = state { stopAudioInput() }
        else if case .error = state { stopAudioInput() }
        else if case .interrupted = state { stopAudioInput() }
    }

    // MARK: - Follow-up

    /// After a spoken reply, briefly listen for a follow-up (Siri-style
    /// conversational turn) without requiring the wake word again.
    private func beginFollowUp() {
        guard settings.voiceFollowUpEnabled, permissionGranted else {
            enterStandby()
            return
        }
        followUpPending = true
        lastPartialAt = .distantPast
        beginCapture()
        let silenceDeadline = Date().addingTimeInterval(8)
        let hardDeadline = Date().addingTimeInterval(20)
        followUpTimeoutTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, case .listening = self.state else { return }
                let partial = self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                let now = Date()
                if partial.isEmpty {
                    if now >= silenceDeadline { self.cancelListening(); return }
                } else if now >= hardDeadline || now.timeIntervalSince(self.lastPartialAt) > 1.5 {
                    // The user paused (or hit the hard cap): end audio so the
                    // recognizer delivers what it has instead of recording on.
                    self.finishListening(); return
                }
            }
        }
    }

    // MARK: - Orchestrator hooks

    func setProcessing() {
        if case .transcribing = state { state = .processing }
        else if case .listening = state { state = .processing }
    }

    /// Resets a stale .processing/.transcribing state after a failed exchange.
    func setIdle() {
        if case .processing = state { enterStandby() }
        else if case .transcribing = state { enterStandby() }
    }

    /// Speak an assistant response (interruptible).
    func speak(_ text: String) {
        guard settings.speakResponses else {
            enterStandby()
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
        maybeStartWakeListening()
    }

    private func fail(_ message: String) {
        stopCapture()
        state = .error(message)
        onError?(message)
        maybeStartWakeListening()
    }
}

extension VoiceSession: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard case .speaking = self.state else { return }
            self.state = .idle
            self.beginFollowUp()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if case .speaking = self.state { self.state = .interrupted }
        }
    }
}
