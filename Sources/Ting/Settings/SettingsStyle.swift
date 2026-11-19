import SwiftUI

/// Preferences typography is deliberately quieter than launcher chrome, but not tiny or pale.
struct SettingsSectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Keep the consequence or purpose with its switch, not in a separate pale form row.
struct SettingsToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    init(_ title: String, detail: String, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13))
                Text(detail)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 3)
        }
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}

extension View {
    func tingSettingsForm() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .controlSize(.regular)
            // Grouped Form supplies its own section inset; do not add another wide margin.
            .contentMargins(.horizontal, 4, for: .scrollContent)
            .contentMargins(.top, 8, for: .scrollContent)
    }
}
