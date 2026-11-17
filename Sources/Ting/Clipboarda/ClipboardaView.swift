// The clipboarda card in the Ting style: graphite card, amber top rule, a search input, the
// history on the left and the preview of the selected item on the right.
import AppKit
import SwiftUI
import TingCore

struct ClipboardaView: View {
    let state: ClipboardaState
    let onChoose: (_ id: Int?, _ paste: Bool) -> Void
    let onDismiss: () -> Void
    let onExclude: (ClipSource) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            ClipboardaCard(state: state, onChoose: onChoose, onDismiss: onDismiss, onExclude: onExclude)
                .padding(.top, 8)
        }
    }
}

private struct ClipboardaCard: View {
    @Bindable var state: ClipboardaState
    let onChoose: (_ id: Int?, _ paste: Bool) -> Void
    let onDismiss: () -> Void
    let onExclude: (ClipSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.showHeader {
                HStack(spacing: 8) {
                    TingMark(size: 14)
                    MonoLabel("Ting  ·  clipboarda", size: 10, tracking: 2).foregroundStyle(Color.tingAmber)
                    Spacer()
                    if !state.shortcut.isEmpty {
                        MonoLabel(state.shortcut, size: 10, weight: .regular, tracking: 1).foregroundStyle(Color.tingMuted)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 14)
            }
            searchBox
            content.padding(.top, 12)
            Rectangle().fill(Color.tingAmber.opacity(0.3)).frame(height: 1).padding(.top, 12)
            HStack(spacing: 14) {
                MonoLabel("↩ paste", size: 9, weight: .regular, tracking: 1)
                MonoLabel("⌘↩ copy", size: 9, weight: .regular, tracking: 1)
                MonoLabel("⇧⌘⌫ remove", size: 9, weight: .regular, tracking: 1)
                MonoLabel("esc close", size: 9, weight: .regular, tracking: 1)
                Spacer()
                MonoLabel("this session only", size: 9, weight: .regular, tracking: 1)
            }
            .foregroundStyle(Color.tingMuted)
            .padding(.top, 10)
        }
        .foregroundStyle(Color.tingInk)
        .padding(.horizontal, 20)
        .padding(.top, state.showHeader ? 20 : 18)
        .padding(.bottom, 16)
        .frame(width: ClipboardaPanel.width - 40)
        .background(Color.soundPanel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .top) { Rectangle().fill(Color.tingAmber).frame(height: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.tingStroke.opacity(0.6), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("clipboarda")
    }

    private var searchBox: some View {
        LaunchaSearchField(text: $state.query, placeholder: "Search the clipboard history",
                           focusToken: state.focusToken,
                           onMove: { state.move(by: $0) },
                           onSubmit: { onChoose(nil, true) },
                           onCancel: onDismiss,
                           accessibilityLabel: "Search the clipboard history",
                           accessibilityHelp: "Up and down arrows choose an item. Return pastes it. Command-Return copies it. Command-Delete removes it. Escape closes clipboarda.")
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.tingInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.tingStroke.opacity(0.7), lineWidth: 0.75))
    }

    @ViewBuilder private var content: some View {
        let results = state.results
        if results.isEmpty {
            Text(emptyMessage)
                .font(.system(size: 12))
                .foregroundStyle(Color.tingMuted)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                .accessibilityAddTraits(.updatesFrequently)
        } else {
            let selected = state.selected
            HStack(alignment: .top, spacing: 14) {
                ClipList(results: results, selectedID: selected?.id, images: state.images, height: state.listHeight,
                         onSelect: { state.select($0) }, onChoose: { onChoose($0, true) })
                    .frame(width: 300)
                Rectangle().fill(Color.tingStroke.opacity(0.5)).frame(width: 0.75)
                if let selected {
                    ClipPreview(entry: selected, images: state.images, onExclude: onExclude)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .id(selected.id)
                }
            }
            .frame(height: state.listHeight)
        }
    }

    private var emptyMessage: String {
        if !state.isRecording { return "Recording is off. Turn it on in Settings › clipboarda." }
        if !state.query.isEmpty { return "Nothing copied in this session matches." }
        return "Nothing copied yet in this session."
    }
}

// MARK: - List

private struct ClipList: View {
    let results: [ClipEntry]
    let selectedID: Int?
    let images: ClipImageCache
    let height: CGFloat
    let onSelect: (Int) -> Void
    let onChoose: (Int) -> Void

    static let rowHeight: CGFloat = 40

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(results) { entry in
                        ClipRow(entry: entry, selected: entry.id == selectedID, images: images) {
                            onSelect(entry.id)
                            onChoose(entry.id)
                        }
                        .id(entry.id)
                    }
                }
            }
            .scrollIndicators(CGFloat(results.count) * Self.rowHeight > height ? .automatic : .never)
            .padding(.horizontal, -8)
            .onChange(of: selectedID) {
                if let selectedID { proxy.scrollTo(selectedID) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clipboard history")
    }
}

private struct ClipRow: View {
    let entry: ClipEntry
    let selected: Bool
    let images: ClipImageCache
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ClipIcon(entry: entry, images: images, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title.isEmpty ? " " : entry.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1).truncationMode(.tail)
                    Text(ClipFormat.subtitle(entry))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.tingMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if entry.copyCount > 1 {
                    Text("×\(entry.copyCount)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.tingAmber)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: ClipList.rowHeight)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.tingAmber.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle(cornerRadius: 6))
        .accessibilityLabel("\(ClipFormat.kindName(entry.content)): \(entry.title)")
        .accessibilityValue(ClipFormat.subtitle(entry))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Pastes it into the app in front")
    }
}

/// The icon of an item: a thumbnail, a Finder icon, a favicon, a color swatch or a symbol.
private struct ClipIcon: View {
    let entry: ClipEntry
    let images: ClipImageCache
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            switch entry.content {
            case .color(let hex):
                RoundedRectangle(cornerRadius: 5)
                    .fill(ClipFormat.color(hex) ?? .clear)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.tingStroke, lineWidth: 0.5))
            case .files(let files):
                Image(nsImage: NSWorkspace.shared.icon(forFile: files.first?.path ?? "/")).resizable().scaledToFit()
            default:
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: ClipFormat.symbol(entry.content))
                        .font(.system(size: size * 0.5, weight: .medium))
                        .foregroundStyle(Color.tingInk.opacity(0.75))
                        .frame(width: size, height: size)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.tingInk.opacity(0.06)))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: entry.id * 31 + (entry.link?.icon?.count ?? 0)) {
            if let (data, key) = ClipFormat.iconData(entry) {
                image = await images.image(data, key: key, maxPixels: Int(size * 2))
            }
        }
    }
}

// MARK: - Preview

private struct ClipPreview: View {
    let entry: ClipEntry
    let images: ClipImageCache
    let onExclude: (ClipSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ClipContentPreview(entry: entry, images: images)
                .frame(maxWidth: .infinity, minHeight: 80, maxHeight: .infinity, alignment: .topLeading)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(Array(ClipFormat.rows(entry).enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.label).foregroundStyle(Color.tingMuted)
                        Text(row.value).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                    }
                }
            }
            .font(.system(size: 11))
            .accessibilityElement(children: .combine)
            if let source = entry.source, source.bundleID != nil {
                Button {
                    onExclude(source)
                } label: {
                    Label("Never Keep from \(source.name)", systemImage: "hand.raised")
                }
                .buttonStyle(QuietButtonStyle())
                .help("Removes the items of \(source.name) and never records it again. Undo in Settings › clipboarda.")
            }
        }
    }
}

private struct ClipContentPreview: View {
    let entry: ClipEntry
    let images: ClipImageCache
    @State private var image: NSImage?

    var body: some View {
        Group {
            switch entry.content {
            case .text(let text, _):
                ScrollView(.vertical) {
                    Text(String(text.prefix(20_000)) + (text.count > 20_000 ? "\n…" : ""))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .link(let url):
                VStack(alignment: .leading, spacing: 8) {
                    if let title = entry.link?.title {
                        Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(3)
                    }
                    Text(url).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.tingAmber)
                        .lineLimit(4).truncationMode(.middle).textSelection(.enabled)
                    if let image { picture(image) }
                    if case .failed(let reason) = entry.link?.state {
                        Label(reason, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Color.tingMuted)
                    } else if entry.link?.state == .loading {
                        ProgressView().controlSize(.small)
                    }
                }
            case .image:
                if let image { picture(image) } else { Color.clear }
            case .files(let files):
                VStack(alignment: .leading, spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: files.first?.path ?? "/"))
                        .resizable().frame(width: 64, height: 64)
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                                Text(file.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                }
            case .color(let hex):
                RoundedRectangle(cornerRadius: 8)
                    .fill(ClipFormat.color(hex) ?? .clear)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.tingStroke, lineWidth: 0.5))
                    .frame(maxWidth: .infinity, maxHeight: 120)
            }
        }
        .task(id: entry.id * 31 + (entry.link?.imageData?.count ?? 0)) {
            if let (data, key) = ClipFormat.pictureData(entry) {
                image = await images.image(data, key: key, maxPixels: 1024)
            }
        }
    }

    private func picture(_ image: NSImage) -> some View {
        Image(nsImage: image).resizable().scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Image preview")
    }
}

// MARK: - Formatting

@MainActor
enum ClipFormat {
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    static func ago(_ date: Date, now: Date = Date()) -> String {
        now.timeIntervalSince(date) < 5 ? "just now" : relative.localizedString(for: date, relativeTo: now)
    }

    static func subtitle(_ entry: ClipEntry) -> String {
        [entry.source?.name, ago(entry.lastCopied)].compactMap { $0 }.joined(separator: "  ·  ")
    }

    static func rows(_ entry: ClipEntry) -> [(label: String, value: String)] {
        var rows = ClipDetails.rows(for: entry)
        rows.append(("Source", entry.source?.name ?? "Unknown"))
        if entry.copyCount > 1 {
            rows.append(("Copied", "\(entry.copyCount) times"))
            rows.append(("First", "\(time.string(from: entry.firstCopied)), \(ago(entry.firstCopied))"))
            rows.append(("Last", "\(time.string(from: entry.lastCopied)), \(ago(entry.lastCopied))"))
        } else {
            rows.append(("Copied", "\(time.string(from: entry.lastCopied)), \(ago(entry.lastCopied))"))
        }
        return rows
    }

    static func kindName(_ content: ClipContent) -> String {
        switch content {
        case .text(_, let rich): rich ? "Rich text" : "Text"
        case .link: "Link"
        case .image: "Image"
        case .files(let files): files.count == 1 ? "File" : "Files"
        case .color: "Color"
        }
    }

    static func symbol(_ content: ClipContent) -> String {
        switch content {
        case .text(_, let rich): rich ? "doc.richtext" : "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .files: "doc"
        case .color: "paintpalette"
        }
    }

    /// The small icon: an image's own picture or a link's favicon.
    static func iconData(_ entry: ClipEntry) -> (Data, String)? {
        switch entry.content {
        case .image: imageData(entry).map { ($0, "image-\(entry.id)") }
        case .link: entry.link?.icon.map { ($0, "favicon-\(entry.id)") }
        default: nil
        }
    }

    /// The large picture of the preview: an image, or the image a link points to.
    static func pictureData(_ entry: ClipEntry) -> (Data, String)? {
        switch entry.content {
        case .image: imageData(entry).map { ($0, "image-\(entry.id)") }
        case .link: entry.link?.imageData.map { ($0, "link-\(entry.id)") }
        default: nil
        }
    }

    private static func imageData(_ entry: ClipEntry) -> Data? {
        let types = [ClipboardTypes.png, ClipboardTypes.jpeg, ClipboardTypes.tiff]
        return types.lazy.compactMap { type in entry.representations.first { $0.type == type }?.data }.first
    }

    /// `#RGB`, `#RRGGBB` or `#RRGGBBAA`.
    static func color(_ hex: String) -> Color? {
        var digits = String(hex.dropFirst())
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        if digits.count == 6 { digits += "FF" }
        guard digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
        return Color(.sRGB, red: Double((value >> 24) & 0xFF) / 255, green: Double((value >> 16) & 0xFF) / 255,
                     blue: Double((value >> 8) & 0xFF) / 255, opacity: Double(value & 0xFF) / 255)
    }
}
