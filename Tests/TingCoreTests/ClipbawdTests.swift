import Foundation
import Testing
@testable import TingCore

@Suite struct ClipbawdTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let safari = ClipSource(bundleID: "com.apple.Safari", name: "Safari")
    private let notes = ClipSource(bundleID: "com.apple.Notes", name: "Notes")

    private func text(_ value: String, rich: Bool = false, from source: ClipSource? = nil) -> ClipCapture {
        var types = [ClipboardTypes.plainText]
        var representations = [ClipRepresentation(type: ClipboardTypes.plainText, data: Data(value.utf8))]
        if rich {
            types.append(ClipboardTypes.rtf)
            representations.append(ClipRepresentation(type: ClipboardTypes.rtf, data: Data("{\\rtf1 \(value)}".utf8)))
        }
        return ClipCapture(types: types, text: value, representations: representations, source: source)
    }

    @Test func htmlHeadHandlesUnicodeBeforeTags() {
        let base = URL(string: "https://example.org/")!
        let head = ClipHTMLHead.parse(Data("İ<TITLE>İstanbul</TITLE><LINK REL='icon' HREF='/icon.png'>".utf8), base: base)
        #expect(head.title == "İstanbul")
        #expect(head.icon?.absoluteString == "https://example.org/icon.png")
    }

    @Test func linkPolicyRejectsTranslatedAndMalformedAddresses() {
        #expect(ClipLinkPolicy.ipv4("-1.2.3.4") == nil)
        for host in ["::FFFF:127.0.0.1", "::127.0.0.1", "64:ff9b::7f00:1", "fe80::1"] {
            #expect(!ClipLinkPolicy.isPublicHost(host))
        }
        #expect(ClipLinkPolicy.isPublicHost("2606:4700:4700::1111"))
    }

    // MARK: Settings

    @Test func settingsDefaultsAndRoundTrip() throws {
        let old = try ConfigCodec.decode(Data("{}".utf8))
        #expect(old.clipbawd == ClipbawdSettings())
        #expect(old.clipbawd.enabled)
        #expect(!old.clipbawd.fetchLinks)
        var config = Config()
        config.clipbawd.hotkey = Hotkey(string: "cmd+shift+v")
        config.clipbawd.excludedApps = ["com.example.bank"]
        config.clipbawd.ignoredPrefixes = ["sk-", "ghp_"]
        config.clipbawd.fetchLinks = true
        #expect(try ConfigCodec.decode(ConfigCodec.encode(config)) == config)
        let clamped = try ConfigCodec.decode(Data(#"{"clipbawd":{"maxItems":5}}"#.utf8))
        #expect(clamped.clipbawd.maxItems == ClipbawdSettings.maxItemsRange.lowerBound)
    }

    @Test func excludeAddsAnAppOnce() {
        var settings = ClipbawdSettings()
        let added = [settings.exclude(app: "com.example.bank"), settings.exclude(app: "com.example.bank"),
                     settings.exclude(app: "  ")]
        #expect(added == [true, false, false])
        #expect(settings.excludedApps == ["com.example.bank"])
    }

    @Test func hotkeyConflicts() {
        var config = Config()
        config.leader = Hotkey(string: "f13")
        config.launcha.hotkey = Hotkey(string: "cmd+space")
        config.clipbawd.hotkey = Hotkey(string: "f13")
        #expect(ConfigValidator.validate(config).map(\.kind) == [.clipbawdHotkeyConflict])
        config.clipbawd.hotkey = Hotkey(string: "cmd+space")
        #expect(ConfigValidator.validate(config).map(\.kind) == [.clipbawdHotkeyConflict])
        config.clipbawd.hotkey = .modifierTap(.leftCommand)
        #expect(ConfigValidator.validate(config).map(\.kind) == [.invalidClipbawdHotkey])
        config.clipbawd.hotkey = Hotkey(string: "cmd+shift+v")
        #expect(ConfigValidator.validate(config).isEmpty)
        #expect(AppShortcutRules.problem(for: Hotkey(string: "cmd+shift+v")!, in: config) == .clipbawd)

        // Off: the key is free and never reported.
        config.clipbawd.enabled = false
        config.clipbawd.hotkey = Hotkey(string: "f13")
        #expect(config.clipbawd.activeHotkey == nil)
        #expect(ConfigValidator.validate(config).isEmpty)
        #expect(AppShortcutRules.problem(for: Hotkey(string: "f13")!, in: config) == .leader)
        config.clipbawd.hotkey = Hotkey(string: "cmd+shift+v")
        #expect(AppShortcutRules.problem(for: Hotkey(string: "cmd+shift+v")!, in: config) == nil)
    }

    // MARK: Classification

    @Test func classification() {
        #expect(ClipContent.classify(text("hello")) == .text("hello", rich: false))
        #expect(ClipContent.classify(text("hello", rich: true)) == .text("hello", rich: true))
        #expect(ClipContent.classify(text("  https://example.com/a?b=1 \n")) == .link("https://example.com/a?b=1"))
        #expect(ClipContent.classify(text("see https://example.com")) == .text("see https://example.com", rich: false))
        #expect(ClipContent.classify(text("ftp://example.com")) == .text("ftp://example.com", rich: false))
        #expect(ClipContent.classify(text("#ff8800")) == .color("#ff8800"))
        #expect(ClipContent.classify(text("#ff88")) == .text("#ff88", rich: false))
        #expect(ClipContent.classify(text(" \n ")) == nil)
        #expect(ClipContent.classify(ClipCapture(types: ["com.example.private"])) == nil)

        let image = ClipImageInfo(width: 10, height: 20, format: "PNG", byteCount: 100)
        let file = ClipFile(path: "/tmp/a.txt", byteCount: 5, isDirectory: false)
        #expect(ClipContent.classify(ClipCapture(types: [ClipboardTypes.png], image: image)) == .image(image))
        #expect(ClipContent.classify(ClipCapture(types: [ClipboardTypes.png], text: "https://example.org/a.png", image: image)) == .image(image))
        // Word adds a picture of the copied text: the item is the text.
        #expect(ClipContent.classify(ClipCapture(types: [ClipboardTypes.rtf, ClipboardTypes.png], text: "Report", image: image))
                == .text("Report", rich: true))
        #expect(ClipContent.classify(ClipCapture(types: [ClipboardTypes.fileURL], text: "a.txt", image: image, files: [file])) == .files([file]))
    }

    // MARK: Recording

    @Test func duplicatesStackInsteadOfDoubling() {
        var history = ClipHistory()
        let rules = ClipRules()
        let first1 = history.record(text("one", from: safari), rules: rules, at: now)
        let second = history.record(text("two"), rules: rules, at: now)
        // Rich and plain copies of the same text are one item; the latest source wins.
        let again = history.record(text("one", rich: true, from: notes), rules: rules, at: now + 5)
        #expect([first1, second, again] == [.added(1), .added(2), .merged(1)])
        #expect(history.entries.map(\.id) == [1, 2])
        let first = history.entries[0]
        #expect(first.copyCount == 2)
        #expect(first.firstCopied == now)
        #expect(first.lastCopied == now + 5)
        #expect(first.source == notes)
        #expect(first.content == .text("one", rich: true))
    }

    @Test func skipRules() {
        var history = ClipHistory()
        let rules = ClipRules(excludedApps: ["com.example.bank"], ignoredPrefixes: ["", "sk-"])
        var marked = text("secret")
        marked.types.append(ClipboardTypes.concealed)
        var hidden = text("secret")
        hidden.privateContext = true
        var results: [ClipRecordResult] = []
        for capture in [marked, hidden, text("x", from: ClipSource(bundleID: "com.example.bank", name: "Bank")),
                        text("  sk-abc"), text("Sk-ating"), text("   ")] {
            results.append(history.record(capture, rules: rules, at: now))
        }
        #expect(results == [.skipped(.marked), .skipped(.privateContext), .skipped(.excludedApp("com.example.bank")),
                            .skipped(.ignoredPrefix("sk-")), .added(1), .skipped(.empty)])
        let big = ClipCapture(types: [ClipboardTypes.png],
                              image: ClipImageInfo(width: 1, height: 1, format: "PNG", byteCount: 0),
                              representations: [ClipRepresentation(type: ClipboardTypes.png,
                                                                   data: Data(count: ClipHistory.maxItemBytes + 1))])
        let tooLarge = history.record(big, rules: rules, at: now)
        #expect(tooLarge == .skipped(.tooLarge))
        #expect(history.entries.count == 1)
    }

    @Test func textDropsItsPicture() {
        var history = ClipHistory()
        var capture = text("Report", rich: true)
        capture.types.append(ClipboardTypes.png)
        capture.image = ClipImageInfo(width: 1, height: 1, format: "PNG", byteCount: 3)
        capture.representations.append(ClipRepresentation(type: ClipboardTypes.png, data: Data([1, 2, 3])))
        _ = history.record(capture, rules: ClipRules(), at: now)
        #expect(history.entries[0].representations.map(\.type) == [ClipboardTypes.plainText, ClipboardTypes.rtf])
    }

    @Test func pruneKeepsTheNewest() {
        var history = ClipHistory(maxItems: 3)
        for index in 1...5 { _ = history.record(text("item \(index)"), rules: ClipRules(), at: now) }
        #expect(history.entries.map(\.title) == ["item 5", "item 4", "item 3"])
        history.promote(id: 3, at: now + 1)
        #expect(history.entries.map(\.id) == [3, 5, 4])
        history.remove(id: 5)
        #expect(history.entries.map(\.id) == [3, 4])
    }

    @Test func removeAllFromAnApp() {
        var history = ClipHistory()
        _ = history.record(text("a", from: safari), rules: ClipRules(), at: now)
        _ = history.record(text("b", from: notes), rules: ClipRules(), at: now)
        history.removeAll(fromApp: "com.apple.Safari")
        #expect(history.entries.map(\.title) == ["b"])
    }

    @Test func search() {
        var history = ClipHistory()
        _ = history.record(text("Привет, мир", from: notes), rules: ClipRules(), at: now)
        _ = history.record(text("https://github.com/bobuk-io/ting", from: safari), rules: ClipRules(), at: now)
        _ = history.record(text("Café menu"), rules: ClipRules(), at: now)
        #expect(history.search("").count == 3)
        #expect(history.search("cafe").map(\.title) == ["Café menu"])
        #expect(history.search("github ting").count == 1)
        #expect(history.search("safari").count == 1)
        #expect(history.search("ghbdtn").map(\.title) == ["Привет, мир"])
        #expect(history.search("nothing").isEmpty)
    }

    // MARK: Details

    @Test func details() {
        var history = ClipHistory()
        _ = history.record(text("one two\nthree\n"), rules: ClipRules(), at: now)
        let rows = ClipDetails.rows(for: history.entries[0])
        #expect(rows.map(\.label) == ["Type", "Characters", "Words", "Lines"])
        #expect(rows.map(\.value) == ["Text", "14", "3", "2"])
        #expect(ClipDetails.lineCount("") == 0)
        #expect(ClipDetails.lineCount("a") == 1)
        #expect(ClipDetails.lineCount("a\nb") == 2)
    }

    // MARK: Links

    @Test func fetchPolicy() {
        for allowed in ["https://example.org/a", "http://github.com", "https://8.8.8.8/", "https://[2606:4700::1111]/"] {
            #expect(ClipLinkPolicy.fetchableURL(allowed) != nil, "\(allowed)")
        }
        for blocked in ["file:///etc/passwd", "https://localhost/", "http://router/", "http://printer.local/",
                        "http://192.168.1.1/", "http://10.0.0.1", "http://172.20.0.1", "http://127.0.0.1:8080",
                        "http://169.254.169.254/latest", "http://100.100.1.1", "http://[::1]/", "http://[fe80::1]/",
                        "http://[fd00::1]/", "https://user:pass@example.org/", "javascript:alert(1)"] {
            #expect(ClipLinkPolicy.fetchableURL(blocked) == nil, "\(blocked)")
        }
    }

    @Test func htmlHead() {
        let base = URL(string: "https://example.org/blog/post")!
        let page = """
        <html><head><meta charset="utf-8">
        <TITLE lang=en>
          Tom &amp; Jerry &#8212; &#x41;BC </title>
        <link rel="apple-touch-icon" href="/touch.png">
        <link href='icons/fav.svg' rel='shortcut icon' type="image/svg+xml">
        """
        let head = ClipHTMLHead.parse(Data(page.utf8), base: base)
        #expect(head.title == "Tom & Jerry — ABC")
        #expect(head.icon?.absoluteString == "https://example.org/blog/icons/fav.svg")

        let bare = ClipHTMLHead.parse(Data("<p>no head".utf8), base: URL(string: "http://example.org:8080/x")!)
        #expect(bare.title == nil)
        #expect(bare.icon?.absoluteString == "http://example.org:8080/favicon.ico")

        let script = ClipHTMLHead.parse(Data(#"<link rel="icon" href="javascript:alert(1)"><link rel=icon href=/i.png>"#.utf8), base: base)
        #expect(script.icon?.absoluteString == "https://example.org/i.png")
    }
}

@Suite struct ClipPrivateWindowTests {
    @Test func checks() {
        #expect(ClipPrivateWindow.check(for: "org.mozilla.firefox") == .title)
        guard case .script(let script) = ClipPrivateWindow.check(for: "com.google.Chrome") else {
            Issue.record("Chrome needs a script")
            return
        }
        #expect(script.contains("mode of front window"))
        #expect(ClipPrivateWindow.check(for: "com.apple.Notes") == nil)
        #expect(ClipPrivateWindow.check(for: nil) == nil)
    }

    @Test func answers() {
        #expect(ClipPrivateWindow.isPrivate(title: "Mozilla Firefox Private Browsing"))
        #expect(ClipPrivateWindow.isPrivate(title: "GitHub — Private Browsing"))
        #expect(!ClipPrivateWindow.isPrivate(title: "GitHub — Mozilla Firefox"))
        #expect(ClipPrivateWindow.isPrivate(mode: "incognito\n"))
        #expect(!ClipPrivateWindow.isPrivate(mode: "normal"))
    }
}

@Suite struct OpenBindingTests {
    @Test func decodeEncodeAndCandidates() throws {
        let config = try ConfigCodec.decode(Data(#"{"items":[{"key":"v","label":"Clips","open":"clipbawd"},{"key":"l","open":"launcha"}]}"#.utf8))
        #expect(config.items == [.open("v", "Clips", .clipbawd), .open("l", "", .launcha)])
        #expect(try ConfigCodec.decode(ConfigCodec.encode(config)) == config)
        #expect(ConfigValidator.validate(config).map(\.kind) == [.missingLeader])
        #expect(LaunchaCandidate.from(config.items).isEmpty)
        #expect(throws: ConfigError.self) { try ConfigCodec.decode(Data(#"{"items":[{"key":"v","open":"finder"}]}"#.utf8)) }
        #expect(throws: ConfigError.self) {
            try ConfigCodec.decode(Data(#"{"items":[{"key":"v","open":"launcha","url":"https://a.b"}]}"#.utf8))
        }
    }
}
