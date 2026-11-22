// Chatta: Ting's ACP agent chat window (general text-only chat and Ting configuration workspace).
import AppKit
import BobukCore
import BobukSystem
import BobukUI
import Observation
import SwiftUI
import TingCore

@MainActor
@Observable
final class ChattaController: NSObject, NSWindowDelegate {
    var mode: ChattaMode = .chat
    var selectedAgent: ACPAgentPreset
    var sandboxed = true

    @ObservationIgnored private let theme: ThemeStore
    @ObservationIgnored private let presentsWindow: Bool
    @ObservationIgnored private let configURL: URL
    @ObservationIgnored private let microAppsFolderURL: () -> URL
    @ObservationIgnored private let setupPromptProvider: () -> String
    @ObservationIgnored private let resourcesDirectory: () -> URL?
    @ObservationIgnored private let openSettings: () -> Void
    @ObservationIgnored private let customClientFactory: ((ChattaMode, ACPAgentPreset, Bool) throws -> ACPClient)?

    @ObservationIgnored private var window: ChromeWindow?
    @ObservationIgnored private var injectedSetupPrompt = false
    @ObservationIgnored private var configuredAgentID: String?
    @ObservationIgnored private var isSwitchingProgrammatically = false

    @ObservationIgnored private(set) lazy var session: AgentChatSession = AgentChatSession(
        makeClient: { [weak self] in
            guard let self else { throw ACPError.disconnected }
            self.injectedSetupPrompt = false
            if let custom = self.customClientFactory {
                return try custom(self.mode, self.selectedAgent, self.sandboxed)
            }
            return try self.makeDefaultClient()
        },
        preparePrompt: { [weak self] text in
            guard let self else { return text }
            let first = !self.injectedSetupPrompt
            let prepared = ChattaPrompt.prepare(
                userMessage: text,
                mode: self.mode,
                isFirstMessage: first,
                setupPrompt: self.setupPromptProvider
            )
            if self.mode == .configure && first {
                self.injectedSetupPrompt = true
            }
            return prepared
        },
        missingModelsMessage: "The agent did not return any models. Check your connection, then reconnect.",
        requiresModelCatalog: { [weak self] in
            self?.selectedAgent.requiresModelCatalog ?? false
        },
        idleTimeout: ChattaSettings().idleTimeout
    )

    var configDirectory: URL { configURL.deletingLastPathComponent() }
    var isVisible: Bool { window?.isVisible ?? false }

    init(
        theme: ThemeStore,
        configURL: URL,
        microAppsFolderURL: @escaping () -> URL,
        presentsWindow: Bool = true,
        setupPromptProvider: (() -> String)? = nil,
        resourcesDirectory: (() -> URL?)? = nil,
        openSettings: (() -> Void)? = nil,
        installedAgents: (() -> [ACPAgentPreset])? = nil,
        customClientFactory: ((ChattaMode, ACPAgentPreset, Bool) throws -> ACPClient)? = nil
    ) {
        self.theme = theme
        self.presentsWindow = presentsWindow
        self.configURL = configURL
        self.microAppsFolderURL = microAppsFolderURL
        self.setupPromptProvider = setupPromptProvider ?? {
            AgentPromptSource.text(environment: ["TING_CONFIG": configURL.path])
        }
        self.resourcesDirectory = resourcesDirectory ?? {
            AgentPromptSource.formatDocument(bundle: .main)
                .map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        }
        self.openSettings = openSettings ?? { SettingsOpener.open() }
        self.customClientFactory = customClientFactory
        let detected = installedAgents?() ?? ACPAgentPreset.detectInstalled().map(\.preset)
        self.selectedAgent = ChattaPrompt.resolveAgent(configuredID: nil, installed: detected)
        super.init()
    }

    func configure(_ settings: ChattaSettings) {
        session.idleTimeout = settings.idleTimeout
        session.initialModel = settings.model
        session.initialEffort = settings.effort
        if settings.agent != configuredAgentID {
            configuredAgentID = settings.agent
            if session.phase == .disconnected && session.messages.isEmpty {
                let installed = ACPAgentPreset.detectInstalled().map(\.preset)
                isSwitchingProgrammatically = true
                selectedAgent = ChattaPrompt.resolveAgent(configuredID: settings.agent, installed: installed)
                isSwitchingProgrammatically = false
            }
        }
    }

    /// Opens the Chatta window (optionally switching mode) and auto-connects when disconnected.
    func open(mode requestedMode: ChattaMode? = nil, autoConnect: Bool = true) {
        if let requestedMode, requestedMode != mode {
            setMode(requestedMode, reconnect: false)
        }
        if presentsWindow {
            let win = ensureWindow()
            AppActivation.activate()
            win.makeKeyAndOrderFront(nil)
            win.orderFrontRegardless()
        }
        if autoConnect && session.phase == .disconnected {
            session.connect()
        } else if session.phase == .ready {
            session.noteActivity()
        }
    }

    /// Toggles visibility of the Chatta window from a global hotkey.
    func toggle() {
        if let win = window, win.isVisible && win.isKeyWindow {
            win.orderOut(nil)
        } else {
            open()
        }
    }

    /// Switches between Chat (text-only) and Configure Ting (config workspace).
    func setMode(_ next: ChattaMode, reconnect: Bool = true) {
        guard next != mode else { return }
        if session.phase != .disconnected || !session.messages.isEmpty {
            session.disconnect()
        }
        mode = next
        injectedSetupPrompt = false
        if reconnect && (presentsWindow || customClientFactory != nil) {
            session.connect()
        }
    }

    /// Starts a clean session in the current mode.
    func newChat() {
        session.disconnect()
        injectedSetupPrompt = false
        if presentsWindow || customClientFactory != nil {
            session.connect()
        }
    }

    /// Called by the view when the user picks a different agent from the composer menu.
    func agentSelectionChanged() {
        guard !isSwitchingProgrammatically else { return }
        injectedSetupPrompt = false
        if (isVisible || customClientFactory != nil) && session.phase == .disconnected {
            session.connect()
        }
    }

    func shutdown() async {
        await session.shutdown()
    }

    // MARK: - Window

    /// Builds the window without putting it on screen (for layout tests).
    func prepareWindow() -> ChromeWindow {
        ensureWindow()
    }

    private static let frameAutosaveName = "io.bobuk.ting.chatta"
    private static let defaultBodySize = NSSize(width: 520, height: 600)
    private static let minimumBodySize = NSSize(width: 400, height: 420)

    private func ensureWindow() -> ChromeWindow {
        if let window { return window }
        let newChatButton = StripButton(glyph: .plus, label: "New chat · ⌘N") { [weak self] _ in
            self?.newChat()
        }
        let settingsButton = StripButton(glyph: .settings, label: "Settings · ⌘,") { [weak self] _ in
            self?.openSettings()
        }
        let size = ChromeMetrics.windowSize(forBody: Self.defaultBodySize)
        let win = ChromeWindow(
            contentRect: NSRect(origin: .zero, size: size),
            theme: theme,
            trailing: [newChatButton, settingsButton],
            resizable: true,
            showsTitle: true
        )
        win.title = "Chatta"
        win.contentMinSize = ChromeMetrics.windowSize(forBody: Self.minimumBodySize)
        win.isReleasedWhenClosed = false
        win.delegate = self
        let hosting = win.setContent(ChattaView(controller: self, theme: theme, onSettings: openSettings))
        // Keep SwiftUI layout updates (mode/agent switches, error banners, transcript growth)
        // from pushing Auto Layout size constraints into the NSWindow frame.
        hosting.sizingOptions = []
        if !win.setFrameUsingName(Self.frameAutosaveName) {
            win.center()
        } else if let screen = win.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if win.frame.height > visible.height + 1 || win.frame.width > visible.width + 1 {
                win.setContentSize(size)
                win.center()
            } else {
                win.setFrame(win.constrainFrameRect(win.frame, to: screen), display: false)
            }
        }
        win.setFrameAutosaveName(Self.frameAutosaveName)
        window = win
        return win
    }

    /// Closing hides the window while keeping the session alive until idleTimeout or Quit.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // MARK: - ACP Launch

    private func makeDefaultClient() throws -> ACPClient {
        let directory: URL
        let access: ACPAccessPolicy
        switch mode {
        case .chat:
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("io.bobuk.ting.chatta", isDirectory: true)
            try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            directory = scratch
            access = .textOnly
        case .configure:
            let dir = configDirectory
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            directory = dir
            let additional = ChattaPrompt.configureAdditionalRoots(
                configDirectory: dir,
                microAppsFolder: microAppsFolderURL(),
                resourcesDirectory: resourcesDirectory()
            )
            access = .workspace(allowWrite: true, autoApproveTools: true, additionalRoots: additional)
        }
        let launch = try selectedAgent.launch(
            in: directory,
            sandboxed: sandboxed,
            access: access,
            clientName: "ting"
        )
        return ACPClient(launch: launch)
    }
}
