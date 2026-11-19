import AppKit
import Combine
import Foundation
import ServiceManagement

/// Application settings, persisted in UserDefaults.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    enum Appearance: String, CaseIterable {
        case system, light, dark
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin"); applyLaunchAtLogin() }
    }
    @Published var autoHideEnabled: Bool {
        didSet { defaults.set(autoHideEnabled, forKey: "autoHideEnabled") }
    }
    @Published var inactivityTimeout: Double { // seconds; 30 default
        didSet { defaults.set(inactivityTimeout, forKey: "inactivityTimeout") }
    }
    @Published var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance"); applyAppearance() }
    }
    @Published var selectedModel: String {
        didSet { defaults.set(selectedModel, forKey: "selectedModel") }
    }
    @Published var ollamaBaseURL: String {
        didSet { defaults.set(ollamaBaseURL, forKey: "ollamaBaseURL") }
    }
    @Published var voiceIdentifier: String {
        didSet { defaults.set(voiceIdentifier, forKey: "voiceIdentifier") }
    }
    @Published var speakingRate: Float { // 0...1 mapped onto AVSpeechUtterance rates
        didSet { defaults.set(speakingRate, forKey: "speakingRate") }
    }
    @Published var speakResponses: Bool {
        didSet { defaults.set(speakResponses, forKey: "speakResponses") }
    }
    @Published var wakeWordEnabled: Bool {
        didSet { defaults.set(wakeWordEnabled, forKey: "wakeWordEnabled") }
    }
    @Published var voiceFollowUpEnabled: Bool {
        didSet { defaults.set(voiceFollowUpEnabled, forKey: "voiceFollowUpEnabled") }
    }
    @Published var automaticMemoryEnabled: Bool {
        didSet { defaults.set(automaticMemoryEnabled, forKey: "automaticMemoryEnabled") }
    }
    @Published var hotkeyKeyCode: Int {
        didSet { defaults.set(hotkeyKeyCode, forKey: "hotkeyKeyCode") }
    }
    @Published var hotkeyModifiers: Int { // Carbon modifier flags
        didSet { defaults.set(hotkeyModifiers, forKey: "hotkeyModifiers") }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }
    @Published var expandWindow: Bool {
        didSet { defaults.set(expandWindow, forKey: "expandWindow") }
    }

    private let defaults = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "launchAtLogin": false,
            "autoHideEnabled": true,
            "inactivityTimeout": 30.0,
            "appearance": "system",
            "selectedModel": "",
            "ollamaBaseURL": "http://localhost:11434",
            "voiceIdentifier": "",
            "speakingRate": 0.5,
            "speakResponses": true,
            "wakeWordEnabled": true,
            "voiceFollowUpEnabled": true,
            "automaticMemoryEnabled": true,
            "hotkeyKeyCode": 49,          // Space
            "hotkeyModifiers": 2048,      // optionKey (Carbon)
            "hasCompletedOnboarding": false,
            "expandWindow": false,
        ])
        launchAtLogin = d.bool(forKey: "launchAtLogin")
        autoHideEnabled = d.bool(forKey: "autoHideEnabled")
        inactivityTimeout = d.double(forKey: "inactivityTimeout")
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "system") ?? .system
        selectedModel = d.string(forKey: "selectedModel") ?? ""
        ollamaBaseURL = d.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        voiceIdentifier = d.string(forKey: "voiceIdentifier") ?? ""
        speakingRate = d.float(forKey: "speakingRate")
        speakResponses = d.bool(forKey: "speakResponses")
        wakeWordEnabled = d.bool(forKey: "wakeWordEnabled")
        voiceFollowUpEnabled = d.bool(forKey: "voiceFollowUpEnabled")
        automaticMemoryEnabled = d.bool(forKey: "automaticMemoryEnabled")
        hotkeyKeyCode = d.integer(forKey: "hotkeyKeyCode")
        hotkeyModifiers = d.integer(forKey: "hotkeyModifiers")
        hasCompletedOnboarding = d.bool(forKey: "hasCompletedOnboarding")
        expandWindow = d.bool(forKey: "expandWindow")
        applyAppearance()
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            XavierLog.general.error("Launch-at-login failed: \(error.localizedDescription)")
        }
    }
}
