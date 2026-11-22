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
    var allowToolsPermanently = false
    var toolsOverrideForSession: Bool? = nil

    var effectiveAllowTools: Bool {
        toolsOverrideForSession ?? allowToolsPermanently
    }

    @ObservationIgnored private let theme: ThemeStore
    @ObservationIgnored private let presentsWindow: Bool
    @ObservationIgnored private let configURL: URL
    @ObservationIgnored private let microAppsFolderURL: () -> URL
    @ObservationIgnored private let setupPromptProvider: () -> String
    @ObservationIgnored private let resourcesDirectory: () -> URL?
    @ObservationIgnored let openSettings: () -> Void
    @ObservationIgnored private let onAllowToolsPermanently: (() -> Void)?
    @ObservationIgnored private let customClientFactory: ((ChattaMode, ACPAgentPreset, Bool, ACPAccessPolicy) throws -> ACPClient)?
    @ObservationIgnored let preferences: AgentChatPreferences

    @ObservationIgnored private var window: ChromeWindow?
    @ObservationIgnored private var injectedSetupPrompt = false
    @ObservationIgnored private var configuredAgentID: String?
    @ObservationIgnored private var configuredModel: String?
    @ObservationIgnored private var configuredEffort: String?
    @ObservationIgnored private var isSwitchingProgrammatically = false

    @ObservationIgnored private(set) lazy var session: AgentChatSession = AgentChatSession(
        makeClient: { [weak self] in
            guard let self else { throw ACPError.disconnected }
            self.injectedSetupPrompt = false
            let access = self.currentAccessPolicy()
            if let custom = self.customClientFactory {
                return try custom(self.mode, self.selectedAgent, self.sandboxed, access)
            }
            return try self.makeDefaultClient(access: access)
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
        idleTimeout: ChattaSettings().idleTimeout,
        onToolAccessChoice: { [weak self] choice in
            guard let self else { return }
            switch choice {
            case .allowAlways:
                self.allowToolsPermanently = true
                self.toolsOverrideForSession = nil
                self.onAllowToolsPermanently?()
            case .allowForSession:
                self.toolsOverrideForSession = true
            case .deny:
                break
            }
        }
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
        onAllowToolsPermanently: (() -> Void)? = nil,
        preferences: AgentChatPreferences? = nil,
        installedAgents: (() -> [ACPAgentPreset])? = nil,
        customClientFactory: ((ChattaMode, ACPAgentPreset, Bool, ACPAccessPolicy) throws -> ACPClient)? = nil
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
        self.openSettings = openSettings ?? { SettingsOpener.open(page: .chatta) }
        self.onAllowToolsPermanently = onAllowToolsPermanently
        self.customClientFactory = customClientFactory
        let detected = installedAgents?() ?? ACPAgentPreset.detectInstalled().map(\.preset)
        let defaultAgent = ChattaPrompt.resolveAgent(configuredID: nil, installed: detected)
        let resolvedPreferences: AgentChatPreferences = if let preferences {
            preferences
        } else {
            AgentChatPreferences(
                defaults: presentsWindow
                    ? .standard
                    : (UserDefaults(suiteName: "io.bobuk.ting.chatta.ephemeral." + UUID().uuidString) ?? .standard),
                keys: .init(agentID: "tingChattaAgentID", model: "tingChattaModel", effort: "tingChattaEffort"),
                agents: ACPAgentPreset.all,
                defaultAgent: defaultAgent
            )
        }
        self.preferences = resolvedPreferences
        if detected.isEmpty || detected.contains(resolvedPreferences.agent) {
            self.selectedAgent = resolvedPreferences.agent
        } else {
            self.selectedAgent = defaultAgent
        }
        super.init()
        self.session.initialModel = resolvedPreferences.model
        self.session.initialEffort = resolvedPreferences.effort
    }

    func configure(_ settings: ChattaSettings) {
        session.idleTimeout = settings.idleTimeout
        configuredModel = settings.model
        configuredEffort = settings.effort
        session.initialModel = settings.model ?? preferences.model
        session.initialEffort = settings.effort ?? preferences.effort
        let toolsChanged = allowToolsPermanently != settings.allowTools
        allowToolsPermanently = settings.allowTools
        if toolsChanged {
            toolsOverrideForSession = nil
            if mode == .chat && session.phase == .ready && session.messages.isEmpty {
                session.reconnectKeepingTranscript()
            }
        }
        if settings.agent != configuredAgentID {
            configuredAgentID = settings.agent
            if session.phase == .disconnected && session.messages.isEmpty {
                let installed = ACPAgentPreset.detectInstalled().map(\.preset)
                isSwitchingProgrammatically = true
                if let explicit = settings.agent {
                    selectedAgent = ChattaPrompt.resolveAgent(configuredID: explicit, installed: installed)
                } else if installed.isEmpty || installed.contains(preferences.agent) {
                    selectedAgent = preferences.agent
                } else {
                    selectedAgent = ChattaPrompt.resolveAgent(configuredID: nil, installed: installed)
                }
                isSwitchingProgrammatically = false
            }
        }
    }

    func recordPreferences() {
        preferences.record(from: session)
        session.initialModel = configuredModel ?? preferences.model
        session.initialEffort = configuredEffort ?? preferences.effort
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
            session.requestComposerFocus()
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

    /// Switches between Chat (text-only / optional tools) and Configure Ting (config workspace).
    func setMode(_ next: ChattaMode, reconnect: Bool = true) {
        guard next != mode else { return }
        if session.phase != .disconnected || !session.messages.isEmpty {
            session.disconnect()
        }
        mode = next
        toolsOverrideForSession = nil
        injectedSetupPrompt = false
        if reconnect && (presentsWindow || customClientFactory != nil) {
            session.connect()
        }
        if presentsWindow { session.requestComposerFocus() }
    }

    /// Starts a clean session in the current mode.
    func newChat() {
        session.disconnect()
        toolsOverrideForSession = nil
        injectedSetupPrompt = false
        if presentsWindow || customClientFactory != nil {
            session.connect()
        }
        if presentsWindow { session.requestComposerFocus() }
    }

    /// Toggles agent tools for the current Chat session and reconnects if active.
    func toggleChatTools() {
        guard mode == .chat else { return }
        guard session.phase == .ready || session.phase == .disconnected else { return }
        let next = !effectiveAllowTools
        toolsOverrideForSession = (next == allowToolsPermanently) ? nil : next
        if session.phase == .ready {
            session.reconnectKeepingTranscript()
        }
    }

    /// Called by the view when the user picks a different agent from the composer menu.
    func agentSelectionChanged() {
        guard !isSwitchingProgrammatically else { return }
        preferences.agent = selectedAgent
        session.initialModel = configuredModel ?? preferences.model
        session.initialEffort = configuredEffort ?? preferences.effort
        injectedSetupPrompt = false
        if customClientFactory == nil, case .needsACPAdapter = selectedAgent.detectAvailability() {
            return
        }
        if (isVisible || customClientFactory != nil) && session.phase == .disconnected {
            session.connect()
        }
    }

    func shutdown() async {
        preferences.record(from: session)
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
        let size = ChromeMetrics.windowSize(forBody: Self.defaultBodySize)
        let win = ChromeWindow(
            contentRect: NSRect(origin: .zero, size: size),
            theme: theme,
            trailing: [newChatButton],
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
        preferences.record(from: session)
        sender.orderOut(nil)
        return false
    }

    // MARK: - ACP Launch

    private func currentAccessPolicy() -> ACPAccessPolicy {
        switch mode {
        case .chat:
            return effectiveAllowTools ? .tools(autoApproveTools: true) : .textOnly
        case .configure:
            let dir = configDirectory
            let additional = ChattaPrompt.configureAdditionalRoots(
                configDirectory: dir,
                microAppsFolder: microAppsFolderURL(),
                resourcesDirectory: resourcesDirectory()
            )
            return .workspace(allowWrite: true, autoApproveTools: true, additionalRoots: additional)
        }
    }

    private func makeDefaultClient(access: ACPAccessPolicy) throws -> ACPClient {
        let directory: URL
        switch mode {
        case .chat:
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("io.bobuk.ting.chatta", isDirectory: true)
            try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            directory = scratch
        case .configure:
            let dir = configDirectory
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            directory = dir
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
