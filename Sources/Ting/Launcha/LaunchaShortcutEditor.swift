import AppKit
import Observation
import SwiftUI
import TingCore

/// Captures keys only in launcha's own panel. It never installs a global keyboard monitor.
@MainActor
@Observable
final class LaunchaShortcutEditor: HotkeyRecordingOwner {
    let row: LaunchaRow
    let original: Hotkey?
    var candidate: Hotkey?
    var preview = ""
    var warning: String?
    var replacement: String?
    private(set) var isFinished = false
    private(set) var isListening = true
    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored var validate: (Hotkey) -> String? = { _ in nil }
    @ObservationIgnored var replacing: (Hotkey) -> String? = { _ in nil }
    @ObservationIgnored var persist: (Hotkey?) throws -> Void = { _ in }

    init(row: LaunchaRow, original: Hotkey?) {
        self.row = row
        self.original = original
        candidate = original
        preview = original?.display ?? ""
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        onFinish?()
    }

    /// After capture, Tab/Space can reach the buttons; Return saves without becoming a new key.
    func handlePanelEvent(_ event: NSEvent) -> Bool {
        if !isListening, event.type == .keyDown,
           event.keyCode == 48 || event.keyCode == 49 { return false }
        capture(event)
        return true
    }

    func recordAgain() {
        isListening = true
        candidate = nil
        preview = ""
        warning = nil
        replacement = nil
    }

    func capture(_ event: NSEvent) {
        guard !isFinished else { return }
        if event.type == .keyDown, event.keyCode == 53 { cancel(); return }
        if !isListening {
            if event.type == .keyDown, event.keyCode == 36 || event.keyCode == 76,
               event.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty { save() }
            return
        }
        let modifiers = ModifierSet(event.modifierFlags).subtracting(.function)
        if event.type == .flagsChanged { preview = modifiers.symbols; return }
        guard event.type == .keyDown, !event.isARepeat else { return }
        let hotkey = Hotkey.combo(keyCode: event.keyCode, modifiers: modifiers)
        candidate = hotkey
        preview = hotkey.display
        warning = validate(hotkey)
        if !hotkey.isValid { warning = AppShortcutRules.Problem.invalidKey.description }
        replacement = warning == nil ? replacing(hotkey) : nil
        if warning == nil { isListening = false }
    }

    func save() {
        guard !isFinished, let candidate else { return }
        warning = validate(candidate)
        guard warning == nil else { return }
        do { try persist(candidate); cancel() }
        catch let error as AppShortcutRules.Problem { warning = error.description }
        catch { warning = error.localizedDescription; isListening = true }
    }

    func remove() {
        guard !isFinished else { return }
        do { try persist(nil); cancel() }
        catch { warning = error.localizedDescription }
    }
}

struct LaunchaShortcutEditorView: View {
    let editor: LaunchaShortcutEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Global shortcut for \(editor.row.name)").font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(editor.preview.isEmpty ? "Press a shortcut…" : editor.preview)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 12)
                .background(Color.tingInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Recorded shortcut")
                .accessibilityValue(editor.preview)
            if let warning = editor.warning {
                Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(Color.tingAmber)
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            } else if let replacement = editor.replacement {
                Text("This shortcut will be removed from \(replacement).")
                    .font(.caption).foregroundStyle(Color.tingAmber)
            } else {
                Text(editor.isListening ? "Press a key, optionally with modifiers. Esc cancels." :
                     "Return saves and replaces this app’s old shortcut. Esc cancels.")
                    .font(.caption).foregroundStyle(Color.tingMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if !editor.isListening {
                    Button("Record Again", action: editor.recordAgain).buttonStyle(QuietButtonStyle())
                }
                if editor.original != nil {
                    Button("Remove", action: editor.remove).buttonStyle(QuietButtonStyle())
                }
                Spacer()
                Button("Cancel", action: editor.cancel).buttonStyle(QuietButtonStyle())
                Button("Save", action: editor.save)
                    .buttonStyle(QuietButtonStyle(prominent: true))
                    .disabled(editor.candidate == nil || editor.warning != nil)
            }
        }
        .padding(.vertical, 12)
    }
}
