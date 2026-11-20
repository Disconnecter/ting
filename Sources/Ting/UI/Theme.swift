// Ting visual language: graphite panels, amber accents and solid amber "Soundsystem" keycaps.
import AppKit
import SwiftUI
import TingCore
import BobukUI
import BobukSystem

/// App-owned colors; BobukKit owns shared picker geometry and rendering.
enum TingPickerStyle {
    static var palette: PickerPalette {
        PickerPalette(surface: TingColors.soundPanel, text: BobukColors.ink, secondary: BobukColors.muted,
                      accent: BobukColors.amber, border: BobukColors.stroke.withAlphaComponent(0.6),
                      badgeInk: TingColors.soundKeyInk)
    }

    /// The toast keeps Ting's graphite capsule with a full-strength outline.
    static var toast: PickerPalette {
        var palette = palette
        palette.surface = BobukColors.panel
        palette.border = BobukColors.stroke
        return palette
    }
}

/// Ting's own "Soundsystem" colors; the graphite and amber shared with the other apps are `BobukColors`.
enum TingColors {
    static let soundPanel = NSColor.dynamic(light: 0xEEEDE6, dark: 0x181C1F)
    static let soundKey = NSColor.dynamic(light: 0xD99A2B, dark: 0xE7BB74)
    static let soundKeyInk = NSColor.dynamic(light: 0x2A1C05, dark: 0x1D1609)
}

extension Appearance {
    var title: String { self == .light ? "Light" : "Dark" }

    /// Ting sets the whole app appearance, so Settings and the leader menu match.
    @MainActor func apply() {
        NSApp.appearance = NSAppearance(named: self == .light ? .aqua : .darkAqua)
    }
}

extension Color {
    static var tingPanel: Color { Color(nsColor: BobukColors.panel) }
    static var tingInk: Color { Color(nsColor: BobukColors.ink) }
    static var tingMuted: Color { Color(nsColor: BobukColors.muted) }
    static var tingAmber: Color { Color(nsColor: BobukColors.amber) }
    static var tingStroke: Color { Color(nsColor: BobukColors.stroke) }

    static var soundPanel: Color { Color(nsColor: TingColors.soundPanel) }
    static var soundKey: Color { Color(nsColor: TingColors.soundKey) }
    static var soundKeyInk: Color { Color(nsColor: TingColors.soundKeyInk) }
}

extension ButtonStyle where Self == QuietButtonStyle {
    /// BobukKit's quiet button in Ting's colors; `prominent` fills it with the soundsystem key.
    static func tingQuiet(prominent: Bool = false) -> QuietButtonStyle {
        QuietButtonStyle(palette: TingPickerStyle.palette, prominent: prominent, prominentFill: TingColors.soundKey)
    }
}

/// Ting mark: a struck dot with two sound arcs.
struct TingMark: View {
    var color: Color = .tingAmber
    var size: CGFloat = 16

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 16
            let dot = CGRect(x: 1 * s, y: 6 * s, width: 4 * s, height: 4 * s)
            context.fill(Path(ellipseIn: dot), with: .color(color))
            for (index, radius) in [5.5, 9.5].enumerated() {
                var arc = Path()
                arc.addArc(center: CGPoint(x: 3 * s, y: 8 * s), radius: radius * s,
                           startAngle: .degrees(-50), endAngle: .degrees(50), clockwise: false)
                context.stroke(arc, with: .color(color.opacity(index == 0 ? 1 : 0.55)),
                               style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The leader is a tuning fork rather than the name of the configured key.
/// Two forks can represent a double-tap in the launcha panel.
struct LeaderToken: View {
    let leader: String
    var taps = 1
    /// The dashed key outline. Off inside the launcha search input.
    var boxed = true
    /// Replaces the default tooltip and spoken label, e.g. to name the launcha hotkey too.
    var description: String?

    var body: some View {
        HStack(spacing: taps > 1 ? 1 : 4) {
            ForEach(0..<taps, id: \.self) { _ in
                Image(nsImage: StatusIcon.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            }
        }
        .foregroundStyle(Color.tingMuted)
        .padding(.horizontal, boxed ? 6 : 0)
        .frame(minWidth: boxed ? 30 : nil, minHeight: boxed ? 30 : nil)
        .overlay {
            if boxed {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color.tingMuted.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(leader: leader, taps: taps, description: description))
        .help(Self.label(leader: leader, taps: taps, description: description))
    }

    /// Tooltip and spoken label: names the real key, and a double tap.
    static func label(leader: String, taps: Int, description: String?) -> String {
        if let description { return description }
        let key = leader.isEmpty ? "Leader key" : "Leader key \(leader)"
        return taps == 1 ? key : "\(key), pressed twice"
    }
}

enum KeyCapStyle { case quiet, sound }

/// A binding key. Shows the active non-Latin layout letter as a small hint.
struct KeyCap: View {
    let key: String
    var style: KeyCapStyle = .sound
    var large = false

    var body: some View {
        let hint = KeyTranslator.localHint(forLatin: key)
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(SequenceKey.display(key))
                .font(.system(size: large ? 15 : 11, weight: .semibold, design: .monospaced))
            if let hint {
                Text(hint.uppercased())
                    .font(.system(size: large ? 9 : 7.5, weight: .medium, design: .monospaced))
                    .opacity(0.55)
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, key.count > 1 && key.hasPrefix("f") ? 4 : 0)
        // One width with or without a layout hint, so the labels of a menu line up.
        .frame(minWidth: large ? 30 : 28, minHeight: large ? 30 : 22)
        .background(background, in: RoundedRectangle(cornerRadius: large ? 7 : 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: large ? 7 : 5, style: .continuous).strokeBorder(border))
        .accessibilityLabel("Key \(SequenceKey.spoken(key))")
    }

    private var foreground: Color {
        switch style {
        case .quiet: .tingInk
        case .sound: .soundKeyInk
        }
    }

    private var background: Color {
        switch style {
        case .quiet: Color.tingInk.opacity(0.07)
        case .sound: .soundKey
        }
    }

    private var border: Color {
        switch style {
        case .quiet: Color.tingInk.opacity(0.12)
        case .sound: .clear
        }
    }
}

/// Row highlight on hover, used by the leader menu rows.
struct HoverRowStyle: ButtonStyle {
    var cornerRadius: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        HoverRow(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct HoverRow: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.tingInk.opacity(configuration.isPressed ? 0.14 : hovering ? 0.06 : 0)))
                .onHover { hovering = $0 }
        }
    }
}

/// App icon for an `.app` item, a globe for a URL, a folder for a group.
struct ItemIcon: View {
    let item: Item
    var size: CGFloat = 18

    var body: some View {
        Group {
            switch item.action {
            case .app(let bundleID):
                if let image = AppIcons.icon(bundleID) {
                    Image(nsImage: image).resizable()
                } else {
                    Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
                }
            case .url:
                Image(systemName: "globe").resizable().foregroundStyle(.secondary)
            case .group:
                Image(systemName: "folder").resizable().foregroundStyle(.secondary)
            case .micro:
                Image(systemName: "terminal").resizable().foregroundStyle(.secondary)
            case .open(let panel):
                Image(systemName: panel.symbol).resizable().foregroundStyle(.secondary)
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    /// Resolve icons while loading bindings, never on the first menu opening.
    static func prepare(_ items: [Item]) {
        missing.removeAll()
        func visit(_ items: [Item]) {
            for item in items {
                switch item.action {
                case .group(let children): visit(children)
                case .app(let id): _ = icon(id)
                default: break
                }
            }
        }
        visit(items)
    }

    static func icon(_ bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard !missing.contains(bundleID) else { return nil }
        guard !bundleID.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missing.insert(bundleID)
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }
}

extension TingPanel {
    var symbol: String {
        switch self {
        case .launcha: "magnifyingglass"
        case .clipbawd: "list.clipboard"
        }
    }
}
