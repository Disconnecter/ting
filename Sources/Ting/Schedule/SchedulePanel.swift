import AppKit
import BobukSystem
import BobukUI
import EventKit
import SwiftUI
import TingCore

final class SchedulePanel: BobukPanel {
    static let width: CGFloat = 640

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
}

@MainActor
final class ScheduleController: NSObject {
    let model: ScheduleModel
    private var panel: SchedulePanel?
    private var observers: [NSObjectProtocol] = []
    private var refreshLoop: Task<Void, Never>?
    private let presentsWindow: Bool
    var onOpenSettings: (() -> Void)?

    var isOpen: Bool { model.isOpen }

    init(model: ScheduleModel, presentsWindow: Bool = true) {
        self.model = model
        self.presentsWindow = presentsWindow
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

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    private func makePanel() -> SchedulePanel {
        let panel = SchedulePanel()
        panel.bindTheme(.ting)
        panel.onDismiss = { [weak self] _ in self?.close() }
        panel.onRefresh = { [weak self] in self?.refresh() }
        panel.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        let view = ScheduleView(model: model,
                                onRefresh: { [weak self] in self?.refresh() },
                                onRequestAccess: { [weak self] in self?.requestAccess() },
                                onOpenPrivacy: { [weak self] in self?.openPrivacySettings() },
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
