import SwiftUI

struct ComposerView: View {
    @Bindable var model: AppModel
    @Environment(\.nanoPalette) private var palette
    @State private var focused = false
    @State private var deliveryHint = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.queuedPrompts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.queuedPrompts) { prompt in
                        HStack(alignment: .top, spacing: 8) {
                            PhosphorIcon(icon: prompt.mode == "steer" ? .arrowUp : .chats, size: 16)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(prompt.label).font(TrigramsFont.medium(11)).foregroundStyle(palette.secondary)
                                Text(prompt.text).font(TrigramsFont.body(13)).textSelection(.enabled)
                            }
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.highlight, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("queue.\(prompt.id)")
                    }
                }.accessibilityIdentifier("queuedPrompts")
            }
            VStack(spacing: 6) {
                NativeTextEditor(text: $model.composerText, identifier: "composerInput", placeholder: String(localized: "Ask Trigrams…"), fontSize: 15, isComposer: true, onSubmit: {
                    if model.isWorking { deliveryHint = true }
                    else { Task { await model.submit() } }
                }, onFocus: { focused = $0 })
                .frame(height: editorHeight)
                HStack(spacing: 8) {
                    TrigramsButton(label: String(localized: "Skills"), icon: .book, identifier: "composerSkillsButton") {
                        model.settingsTab = .skills
                        model.settingsVisible = true
                    }
                    Spacer(minLength: 4)
                    if model.isWorking {
                        TrigramsButton(label: String(localized: "Steer now"), identifier: "steerButton") { Task { await model.submit(mode: "steer") } }
                            .disabled(!model.canSend)
                        TrigramsButton(label: String(localized: "Queue after completion"), variant: .outlined, identifier: "followUpButton") { Task { await model.submit(mode: "followUp") } }
                            .disabled(!model.canSend)
                        IconButton(icon: .stop, label: String(localized: "Stop"), variant: .primary, identifier: "stopButton") { Task { await model.stopGeneration() } }
                            .disabled(model.isStopping)
                            .keyboardShortcut(".", modifiers: .command)
                    } else {
                        IconButton(icon: .arrowUp, label: String(localized: "Send"), variant: .primary, identifier: "sendButton") { Task { await model.submit() } }
                            .disabled(!model.canSend)
                    }
                }
                .padding(.horizontal, 4).padding(.bottom, 4)
            }
            .padding(10)
            .background(palette.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(focused ? palette.salient : palette.inputBorder, lineWidth: focused ? 2 : 1) }
            if model.isWorking, deliveryHint {
                Text("Choose how to deliver your message while Trigrams is working.")
                    .font(TrigramsFont.body(12)).foregroundStyle(palette.secondary)
            }
            if !model.modelAvailable, model.connection == .ready {
                HStack(alignment: .top, spacing: 8) {
                    PhosphorIcon(icon: .warning, size: 16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple On-Device is unavailable").font(TrigramsFont.medium(12))
                        if !model.modelReason.isEmpty { Text(model.modelReason).font(TrigramsFont.body(12)).textSelection(.enabled) }
                    }
                }.foregroundStyle(palette.warningText).accessibilityIdentifier("modelUnavailableMessage")
            }
        }
        .frame(maxWidth: 760)
        .padding(.horizontal, 32).padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(palette.background)
        .onChange(of: model.composerText) { model.syncEditorText() }
        .onChange(of: model.isWorking) { if !model.isWorking { deliveryHint = false } }
    }
    private var editorHeight: CGFloat {
        let lines = model.composerText.split(separator: "\n", omittingEmptySubsequences: false).count
        return min(200, max(52, CGFloat(lines) * 23 + 12))
    }
}
