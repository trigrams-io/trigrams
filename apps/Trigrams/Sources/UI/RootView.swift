import AppKit
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var sidebarWidth: CGFloat = 256
    @State private var dragStartWidth: CGFloat?
    private var palette: NanoPalette { NanoPalette(isDark: model.theme == .dark || model.theme == .system && colorScheme == .dark) }
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                titlebar
                DividerLine()
                HStack(spacing: 0) {
                    if model.sidebarVisible {
                        SidebarView(model: model).frame(width: sidebarWidth)
                        sidebarDivider
                    }
                    VStack(spacing: 0) {
                        chatHeader
                        DividerLine()
                        if model.connection == .starting { startupStatus }
                        TranscriptView(model: model)
                        if let error = model.errorMessage { errorCard(error) }
                        DividerLine()
                        ComposerView(model: model)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .allowsHitTesting(!modalVisible)
            .accessibilityHidden(modalVisible)
            if model.showModelDetails { modelDetails.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.top, 90).padding(.trailing, 20) }
            if model.settingsVisible { overlay { SettingsView(model: model) } }
            if model.branchVisible { overlay { BranchCard(model: model) } }
            if model.compatibilityVisible { overlay { CompatibilityPanel(model: model) } }
            if let dialog = model.dialog { overlay { ExtensionDialogCard(dialog: dialog, model: model).id(dialog.id) } }
        }
        .font(TrigramsFont.body())
        .foregroundStyle(palette.foreground)
        .background(palette.background)
        .environment(\.nanoPalette, palette)
        .preferredColorScheme(model.theme == .system ? nil : model.theme == .dark ? .dark : .light)
        .background { WindowConfiguration().frame(width: 0, height: 0) }
        .frame(minWidth: 800, minHeight: 560)
        .ignoresSafeArea()
        .task { await model.start() }
    }
    private var modalVisible: Bool { model.settingsVisible || model.branchVisible || model.dialog != nil || model.compatibilityVisible }
    private var titlebar: some View {
        HStack(spacing: 10) {
            // Leave room for AppKit's standard traffic lights.
            Color.clear.frame(width: 68, height: 1).accessibilityHidden(true)
            IconButton(icon: .sidebar, label: String(localized: "Toggle sidebar"), identifier: "sidebarToggleButton") { model.sidebarVisible.toggle() }
                .keyboardShortcut("b", modifiers: .command)
            Image("trigrams-mark").resizable().renderingMode(.template).scaledToFit()
                .frame(width: 28, height: 28).foregroundStyle(palette.salient).accessibilityHidden(true)
            Text("Trigrams").font(TrigramsFont.medium(15))
            Spacer()
            Text(model.selectedSession?.title ?? String(localized: "New chat"))
                .font(TrigramsFont.medium(13)).lineLimit(1).foregroundStyle(palette.secondary)
                .accessibilityIdentifier("chatTitle")
            Spacer()
            if !model.sidebarVisible {
                IconButton(icon: .plus, label: String(localized: "New chat"), identifier: "newChatButton") { Task { await model.newChat() } }
                    .disabled(model.connection != .ready || model.isLoading || model.isWorking)
                    .keyboardShortcut("n", modifiers: .command)
                IconButton(icon: .settings, label: String(localized: "Settings"), identifier: "settingsButton") { model.settingsVisible = true }
            }
        }
        .padding(.horizontal, 10).frame(height: 46)
        .background(palette.highlight)
    }
    private var chatHeader: some View {
        HStack(spacing: 10) {
            PhosphorIcon(icon: .folder, size: 16).foregroundStyle(palette.secondary)
            Text(model.selectedSession?.cwd ?? String(localized: "Local workspace"))
                .font(TrigramsFont.body(12)).foregroundStyle(palette.secondary).lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled).accessibilityIdentifier("workingDirectory")
            Spacer(minLength: 8)
            Button { model.showModelDetails.toggle() } label: {
                HStack(spacing: 6) {
                    Text(model.modelName).font(TrigramsFont.medium(12))
                    PhosphorIcon(icon: model.modelAvailable ? .caretDown : .warning, size: 16)
                }
            }
            .buttonStyle(TrigramsButtonStyle())
            .foregroundStyle(model.modelAvailable ? palette.accentText : palette.warningText)
            .accessibilityLabel(model.modelName)
            .accessibilityValue(model.modelAvailable ? String(localized: "Available") : String(localized: "Unavailable"))
            .accessibilityIdentifier("modelStatus")
            IconButton(icon: .branch, label: String(localized: "Branch"), identifier: "branchButton") { Task { await model.showBranches() } }
                .disabled(model.selectedSession == nil || model.isWorking)
        }
        .padding(.horizontal, 18).frame(height: 48)
    }
    private var sidebarDivider: some View {
        Rectangle().fill(palette.subtle).frame(width: 4)
            .contentShape(Rectangle())
            .onHover { hover in if hover { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if dragStartWidth == nil { dragStartWidth = sidebarWidth }
                sidebarWidth = min(320, max(220, (dragStartWidth ?? 256) + value.translation.width))
            }.onEnded { _ in dragStartWidth = nil })
            .accessibilityLabel(String(localized: "Sidebar width"))
            .accessibilityValue("\(Int(sidebarWidth))")
            .accessibilityAdjustableAction { direction in sidebarWidth = min(320, max(220, sidebarWidth + (direction == .increment ? 10 : -10))) }
    }
    private var startupStatus: some View {
        HStack(spacing: 8) {
            PhosphorIcon(icon: .reload, size: 16)
            Text("Starting local runtime…").font(TrigramsFont.body(12))
            Spacer()
        }.foregroundStyle(palette.secondary).padding(.horizontal, 32).padding(.top, 12)
    }
    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            PhosphorIcon(icon: .warning)
            Text(message).font(TrigramsFont.body(13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if model.connection == .failed {
                TrigramsButton(label: String(localized: "Retry"), icon: .reload, variant: .outlined, identifier: "retryRuntimeButton") { Task { await model.retryStartup() } }
            }
        }
        .foregroundStyle(palette.errorText)
        .padding(12).background(palette.highlight, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 32).padding(.bottom, 12)
        .accessibilityIdentifier("runtimeError")
    }
    private var modelDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.modelName).font(TrigramsFont.medium(14))
                Spacer()
                IconButton(icon: .close, label: String(localized: "Close model details"), identifier: "closeModelDetailsButton") { model.showModelDetails = false }
            }
            Text(model.modelAvailable ? String(localized: "Available on this Mac") : String(localized: "Apple On-Device is unavailable"))
                .font(TrigramsFont.medium(12)).foregroundStyle(model.modelAvailable ? palette.successText : palette.warningText)
            if !model.modelReason.isEmpty { Text(model.modelReason).font(TrigramsFont.body(13)).textSelection(.enabled) }
            Text("Provider: Apple Foundation Models").font(TrigramsFont.body(12)).foregroundStyle(palette.secondary)
            Text("Text and structured generation. Image input and thinking levels are unavailable.")
                .font(TrigramsFont.body(12)).foregroundStyle(palette.secondary)
        }
        .padding(16).frame(width: 320)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(palette.inputBorder, lineWidth: 1) }
        .accessibilityIdentifier("modelDetails")
    }
    private func overlay<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            palette.foreground.opacity(0.18).ignoresSafeArea().accessibilityHidden(true)
            content()
        }
    }
}
