import AppKit
import BobukSystem
import BobukUI
import EventKit
import SwiftUI
import TingCore

final class SchedulePanel: BobukPanel {
    static let width: CGFloat = 640

    var onMove: ((Int) -> Void)?
    var onJoin: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 620), kind: .launcher)
        hasShadow = false
        onCommandKey = { [unowned self] event, _ in
            if KeyEquivalent.isCommand(event, latin: "r") {
                if !event.isARepeat { onRefresh?() }
                return true
            }
            if SettingsOpener.isShortcut(latin: KeyEquivalent.latin(of: event), flags: event.modifierFlags) {
                if !event.isARepeat { onOpenSettings?() }
                return true
            }
            return false
        }
    }

    override func sendEvent(_ event: NSEvent) {
        let composing = KeyEquivalent.isComposing(in: self)
        if event.type == .keyDown,
           let delta = LaunchaPanel.navigationDelta(keyCode: event.keyCode, flags: event.modifierFlags,
                                                    composing: composing) {
            onMove?(delta)
            return
        }
        if event.type == .keyDown, VirtualKey.isReturn(event.keyCode), !composing,
           event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
            onJoin?()
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class ScheduleController: NSObject {
    typealias OpenMeeting = (URL) -> Bool

    let model: ScheduleModel
    private var panel: SchedulePanel?
    private var observers: [NSObjectProtocol] = []
    private var refreshLoop: Task<Void, Never>?
    private let presentsWindow: Bool
    private let openMeeting: OpenMeeting
    var onOpenSettings: (() -> Void)?

    var isOpen: Bool { model.isOpen }

    init(model: ScheduleModel, presentsWindow: Bool = true, openMeeting: OpenMeeting? = nil) {
        self.model = model
        self.presentsWindow = presentsWindow
        self.openMeeting = openMeeting ?? { NSWorkspace.shared.open($0) }
        super.init()
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        observers.append(NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isOpen else { return }
                    Task { await self.model.refresh() }
                }
            })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func configure(_ config: Config) { model.configure(config) }

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        guard !isOpen else { return }
        model.setOpen(true)
        Task { await model.refresh() }
        refreshLoop?.cancel()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard let self, self.isOpen else { return }
                await self.model.refresh()
            }
        }
        guard presentsWindow else { return }
        let panel = self.panel ?? makePanel()
        if let visible = Screens.underPointer?.visibleFrame {
            let top = PanelPlacement.top(in: visible, anchor: .upper())
            let height = max(400, min(680, top - visible.minY - 20))
            let width = min(SchedulePanel.width, visible.width - 40)
            panel.setFrame(NSRect(x: visible.midX - width / 2, y: top - height, width: width, height: height), display: false)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func close() {
        guard isOpen else { return }
        refreshLoop?.cancel()
        refreshLoop = nil
        model.setOpen(false)
        panel?.orderOut(nil)
    }

    func refresh() { Task { await model.refresh() } }
    func requestAccess() { Task { await model.requestAccess() } }

    func join(eventID: String? = nil) {
        if let eventID { model.select(eventID) }
        guard let event = model.selectedEvent else { return }
        guard let meeting = event.meeting else {
            model.showMessage("No meeting link found in \(event.title).")
            return
        }
        guard openMeeting(meeting.url) else {
            model.showMessage("Could not open the \(meeting.platform.title) meeting.")
            return
        }
        close()
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    private func makePanel() -> SchedulePanel {
        let panel = SchedulePanel()
        panel.bindTheme(.ting)
        panel.onDismiss = { [weak self] _ in self?.close() }
        panel.onMove = { [weak self] delta in self?.model.moveSelection(by: delta) }
        panel.onJoin = { [weak self] in self?.join() }
        panel.onRefresh = { [weak self] in self?.refresh() }
        panel.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        let view = ScheduleView(model: model,
                                onRefresh: { [weak self] in self?.refresh() },
                                onRequestAccess: { [weak self] in self?.requestAccess() },
                                onOpenPrivacy: { [weak self] in self?.openPrivacySettings() },
                                onSelect: { [weak self] id in self?.model.select(id) },
                                onJoin: { [weak self] id in self?.join(eventID: id) },
                                onOpenSettings: { [weak self] in self?.onOpenSettings?() })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    func suspendKeys() { panel?.suspendDismissal() }
    func resumeKeys() { panel?.resumeDismissal() }
}
