import SwiftUI

enum Phosphor: String {
    case chats, plus, magnifyingGlass = "magnifying-glass", sidebar = "sidebar-simple"
    case arrowUp = "arrow-up", stop, paperclip, folder = "folder-open", book = "book-open"
    case puzzle = "puzzle-piece", terminal = "terminal-window", branch = "git-branch"
    case reload = "arrows-clockwise", settings = "gear-six", sun, moon, more = "dots-three"
    case check = "check-circle", warning = "warning-circle", close = "x", minus, expand = "arrows-out"
    case caretDown = "caret-down", caretRight = "caret-right", arrowLeft = "arrow-left", copy
}

struct PhosphorIcon: View {
    let icon: Phosphor
    var size: CGFloat = 18
    var body: some View {
        Image("phosphor-\(icon.rawValue)")
            .resizable().renderingMode(.template).scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

enum ButtonVariant { case plain, outlined, primary, selected }

struct TrigramsButtonStyle: ButtonStyle {
    var variant: ButtonVariant = .plain
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, variant: variant, compact: compact)
    }

    private struct StyledButton: View {
        let configuration: Configuration
        let variant: ButtonVariant
        let compact: Bool
        @Environment(\.nanoPalette) private var palette
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(TrigramsFont.medium(13))
                .foregroundStyle(variant == .primary ? palette.actionForeground : palette.foreground)
                .padding(.horizontal, compact ? 6 : 12)
                .padding(.vertical, compact ? 6 : 8)
                .frame(minHeight: 32)
                .background(background, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).stroke(focused ? palette.salient : variant == .outlined ? palette.inputBorder : .clear, lineWidth: focused ? 2 : 1)
                }
                .opacity(enabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        }
        private var background: Color {
            if variant == .primary { return palette.salient.opacity(configuration.isPressed ? 0.8 : 1) }
            if configuration.isPressed || variant == .selected { return palette.subtle }
            if hovering { return palette.subtle.opacity(0.65) }
            return .clear
        }
    }
}

struct TrigramsButton: View {
    let label: String
    var icon: Phosphor?
    var variant: ButtonVariant = .plain
    var identifier: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { PhosphorIcon(icon: icon) }
                Text(label)
            }
        }
        .buttonStyle(TrigramsButtonStyle(variant: variant))
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? "")
    }
}

struct IconButton: View {
    let icon: Phosphor
    let label: String
    var variant: ButtonVariant = .plain
    var identifier: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) { PhosphorIcon(icon: icon).frame(width: 20, height: 20) }
            .buttonStyle(TrigramsButtonStyle(variant: variant, compact: true))
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier ?? "")
            .help(label)
    }
}

struct FieldSurface<Content: View>: View {
    @Environment(\.nanoPalette) private var palette
    var focused = false
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(10)
            .background(palette.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(focused ? palette.salient : palette.inputBorder, lineWidth: focused ? 2 : 1) }
    }
}

struct StatusBadge: View {
    let status: RunStatus
    @Environment(\.nanoPalette) private var palette
    var body: some View {
        HStack(spacing: 5) {
            PhosphorIcon(icon: status == .idle ? .check : status == .working ? .reload : .warning, size: 16)
            Text(status.label).font(TrigramsFont.body(12))
        }
        .foregroundStyle(status == .error ? palette.errorText : status == .idle ? palette.successText : palette.secondary)
        .accessibilityElement(children: .combine)
    }
}

struct CustomToggle: View {
    let label: String
    let isOn: Bool
    let identifier: String
    let action: () -> Void
    @Environment(\.nanoPalette) private var palette
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(isOn ? String(localized: "Enabled") : String(localized: "Disabled"))
                    .font(TrigramsFont.body(12)).foregroundStyle(palette.secondary)
                Capsule().fill(isOn ? palette.salient : palette.secondary)
                    .frame(width: 32, height: 18)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(palette.actionForeground).frame(width: 12, height: 12).padding(3)
                    }
            }
            .padding(5)
            .contentShape(Rectangle())
        }
        .buttonStyle(TrigramsButtonStyle(compact: true))
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? String(localized: "Enabled") : String(localized: "Disabled"))
        .accessibilityIdentifier(identifier)
    }
}

struct DividerLine: View {
    @Environment(\.nanoPalette) private var palette
    var body: some View { Rectangle().fill(palette.subtle).frame(height: 1).accessibilityHidden(true) }
}
