// Record any non-modifier key, alone or with modifiers.
import AppKit
import SwiftUI
import TingCore

@MainActor
@Observable
final class HotkeyRecording: HotkeyRecordingOwner {
    private(set) var isRecording = false
    private(set) var preview = ""
    private(set) var warning: String?
    @ObservationIgnored private let monitor = KeyMonitor()
    @ObservationIgnored private var model: AppModel?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private var target = LauncherHotkey.leader

    func start(model: AppModel, target: LauncherHotkey = .leader) {
        // Starting again first stops this recording's monitor and observer.
        stopListening()
        self.model = model
        self.target = target
        isRecording = true
        preview = ""
        warning = nil
        // Cancels any other recording and keeps the hotkeys off until this one ends.
        model.beginHotkeyRecording(self)
        monitor.start { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        // Leaving Ting stops recording, so the old leader never stays switched off.
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    func cancel() {
        guard isRecording else { return }
        isRecording = false
        preview = ""
        stopListening()
        model?.endHotkeyRecording(self)
    }

    private func stopListening() {
        monitor.stop()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let modifiers = ModifierSet(event.modifierFlags).subtracting(.function)
        switch event.type {
        case .flagsChanged:
            // Modifiers may be held as part of a combination, but are never leaders alone.
            preview = modifiers.symbols
            return nil
        case .keyDown:
            let hotkey = Hotkey.combo(keyCode: event.keyCode, modifiers: modifiers)
            let config = model?.config
            if KeyCodes.name(for: event.keyCode) == nil || !hotkey.isValid {
                warning = "A modifier alone cannot \(target.role). Press any other key."
            } else if let config, let owner = LauncherHotkey.owner(of: hotkey, in: config, excluding: target) {
                warning = owner.conflict(for: hotkey) + " Press another key."
            } else {
                finish(hotkey)
            }
            return nil
        default:
            return event
        }
    }

    private func finish(_ hotkey: Hotkey) {
        warning = nil
        cancel()
        switch target {
        case .leader: model?.setLeader(hotkey)
        case .alternateLeader: model?.update { $0.alternateLeader = hotkey }
        case .launcha: model?.setLaunchaHotkey(hotkey)
        case .clipbawd: model?.setClipbawdHotkey(hotkey)
        }
    }
}

/// Large "press your leader" surface, used in Welcome and General settings.
struct LeaderField: View {
    @Environment(AppModel.self) private var model
    @State private var recording = HotkeyRecording()
    var alternate = false
    var large = false
    /// Welcome starts listening at once: the user just presses the leader.
    var autoStart = false

    var body: some View {
        let target: LauncherHotkey = alternate ? .alternateLeader : .leader
        let key = target.configured(in: model.config)
        let name = alternate ? "Second leader key" : "Leader key"
        let isRecording = recording.isRecording
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if isRecording { recording.cancel() } else { recording.start(model: model, target: target) }
            } label: {
                HStack(spacing: 10) {
                    if isRecording {
                        Circle().fill(Color.tingAmber).frame(width: 7, height: 7)
                        let preview = recording.preview
                        Text(preview.isEmpty ? "Press your leader…" : preview)
                            .foregroundStyle(preview.isEmpty ? Color.tingMuted : Color.tingInk)
                    } else if let hotkey = key {
                        Text(hotkey.display)
                    } else {
                        Text("Click to record").foregroundStyle(Color.tingMuted)
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: large ? 20 : 13, weight: .semibold, design: .monospaced))
                .padding(.horizontal, large ? 16 : 10)
                .frame(minWidth: large ? 0 : 200, maxWidth: large ? .infinity : 200)
                .frame(height: large ? 56 : 28)
                .contentShape(Rectangle())
                .background(Color.tingInk.opacity(0.05), in: RoundedRectangle(cornerRadius: large ? 10 : 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: large ? 10 : 6, style: .continuous)
                    .strokeBorder(isRecording ? Color.tingAmber : Color.tingInk.opacity(0.12),
                                  style: StrokeStyle(lineWidth: isRecording ? 1.5 : 1, dash: isRecording ? [4, 3] : [])))
            }
            .buttonStyle(.plain)
            .onAppear { if autoStart && model.config.leaders.isEmpty { recording.start(model: model, target: target) } }
            .onDisappear { recording.cancel() }
            // The config file changed the leader while recording: show the new one.
            .onChange(of: key) { recording.cancel() }
            .accessibilityLabel(key.map { "\(name) \($0.display). Click to change." } ?? "Record \(name)")

            if let warning = recording.warning {
                hint(warning, symbol: "exclamationmark.triangle", color: .tingAmber)
            } else if let problem = model.leaderProblem(alternate: alternate), !isRecording {
                hint(problem, symbol: "exclamationmark.triangle", color: .tingAmber)
            } else if large {
                Text("Press any key: Home, Space, A, F13, or a combination such as ⌥⇧⌘F. Modifiers alone cannot be leaders.")
                    .font(.caption).foregroundStyle(Color.tingMuted)
            }
        }
    }

    private func hint(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Records the separate launcha hotkey. It starts unset; Clear removes it.
struct LaunchaHotkeyField: View {
    var body: some View { WindowHotkeyField(target: .launcha) }
}

/// Records the clipbawd hotkey. It starts unset; Clear removes it.
struct ClipbawdHotkeyField: View {
    var body: some View { WindowHotkeyField(target: .clipbawd) }
}

/// The hotkey of a Ting window (launcha or clipbawd).
private struct WindowHotkeyField: View {
    let target: LauncherHotkey
    @Environment(AppModel.self) private var model
    @State private var recording = HotkeyRecording()

    private var name: String { target == .clipbawd ? "Clipbawd" : "launcha" }
    private var hotkey: Hotkey? { target == .clipbawd ? model.config.clipbawd.hotkey : model.config.launcha.hotkey }
    private var problem: String? { target == .clipbawd ? model.clipbawdHotkeyProblem : model.launchaHotkeyProblem }
    private func set(_ hotkey: Hotkey?) {
        if target == .clipbawd { model.setClipbawdHotkey(hotkey) } else { model.setLaunchaHotkey(hotkey) }
    }

    var body: some View {
        let isRecording = recording.isRecording
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if isRecording { recording.cancel() } else { recording.start(model: model, target: target) }
                } label: {
                    HStack(spacing: 10) {
                        if isRecording {
                            Circle().fill(Color.tingAmber).frame(width: 7, height: 7)
                            let preview = recording.preview
                            Text(preview.isEmpty ? "Press a key…" : preview)
                                .foregroundStyle(preview.isEmpty ? Color.tingMuted : Color.tingInk)
                        } else if let hotkey {
                            Text(hotkey.display)
                        } else {
                            Text("Not set").foregroundStyle(Color.tingMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .frame(width: 160)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .background(Color.tingInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isRecording ? Color.tingAmber : Color.tingInk.opacity(0.12),
                                      style: StrokeStyle(lineWidth: isRecording ? 1.5 : 1, dash: isRecording ? [4, 3] : [])))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hotkey.map { "\(name) hotkey \($0.display). Click to change." }
                                    ?? "Record a \(name) hotkey")
                if hotkey != nil, !isRecording {
                    Button("Clear") { set(nil) }
                        .accessibilityLabel("Clear the \(name) hotkey")
                }
            }
            .onDisappear { recording.cancel() }
            .onChange(of: hotkey) { recording.cancel() }

            if let warning = recording.warning {
                Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Color.tingAmber)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let problem, !isRecording {
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Color.tingAmber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
