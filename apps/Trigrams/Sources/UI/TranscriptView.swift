import SwiftUI

struct TranscriptView: View {
    @Bindable var model: AppModel
    @Environment(\.nanoPalette) private var palette
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if visibleMessages.isEmpty {
                        emptyState.padding(.top, 110)
                    } else {
                        ForEach(visibleMessages) { message in
                            messageView(message)
                        }
                        ForEach(unplacedTools) { tool in ToolRecordView(tool: tool) }
                    }
                    if !visibleMessages.isEmpty || model.isWorking {
                        HStack {
                            StatusBadge(status: model.runStatus)
                            if model.isStopping { Text("Stopping…").font(TrigramsFont.body(12)).foregroundStyle(palette.secondary) }
                            Spacer()
                        }.accessibilityIdentifier("runStatus")
                    }
                    ForEach(Array(model.extensionStatuses.sorted(by: { $0.key < $1.key })), id: \.key) { _, value in
                        Text(value).font(TrigramsFont.body(12)).foregroundStyle(palette.secondary)
                    }
                    ForEach(Array(model.extensionWidgets.sorted(by: { $0.key < $1.key })), id: \.key) { _, value in
                        Text(value).font(TrigramsFont.body()).textSelection(.enabled).padding(12).background(palette.highlight, in: RoundedRectangle(cornerRadius: 8))
                    }
                    ForEach(Array(model.extensionNotifications.enumerated()), id: \.offset) { _, notice in
                        Text(notice).font(TrigramsFont.body()).textSelection(.enabled).foregroundStyle(palette.secondary)
                    }
                    Color.clear.frame(height: 1).id("transcriptBottom")
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 32).padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("chatTranscript")
            .onChange(of: model.messages.count) { proxy.scrollTo("transcriptBottom", anchor: .bottom) }
            .onChange(of: model.messages.last?.text) { if model.isWorking { proxy.scrollTo("transcriptBottom", anchor: .bottom) } }
        }
    }
    private var visibleMessages: [ChatMessage] {
        model.messages.filter { $0.role != "system" && $0.role != "toolResult" }
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image("trigrams-mark").resizable().renderingMode(.template).scaledToFit()
                .frame(width: 52, height: 52).foregroundStyle(palette.salient).accessibilityHidden(true)
            Text("What would you like to do?").font(TrigramsFont.medium(25)).foregroundStyle(palette.strong)
            Text("Work with your files, tools, and skills in a local conversation.")
                .font(TrigramsFont.body(15)).lineSpacing(6).foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var unplacedTools: [ToolExecution] {
        let shown = Set(model.messages.flatMap(\.toolCalls).compactMap { $0["id"].string })
        return model.tools.filter { !shown.contains($0.id) }
    }
    @ViewBuilder private func messageView(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message.label).font(TrigramsFont.medium(12)).foregroundStyle(palette.secondary)
            if !message.text.isEmpty {
                if message.role == "user" {
                    Text(message.text).font(TrigramsFont.body(15)).lineSpacing(6).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("message.\(message.id).content")
                } else {
                    MarkdownView(text: message.text).accessibilityIdentifier("message.\(message.id).content")
                }
            }
            if !message.thinking.isEmpty { ThinkingRecord(text: message.thinking) }
            ForEach(Array(message.toolCalls.enumerated()), id: \.offset) { _, call in
                if let tool = model.tools.first(where: { $0.id == call["id"].string }) { ToolRecordView(tool: tool) }
            }
            if message.role != "user", message.role != "assistant", message.text.isEmpty {
                Text(message.raw.formatted).font(TrigramsFont.code()).textSelection(.enabled)
            }
            if let error = message.raw["errorMessage"].string, !error.isEmpty {
                Text(error).font(TrigramsFont.body()).foregroundStyle(palette.errorText).textSelection(.enabled)
            }
        }
        .padding(message.role == "user" ? 16 : 0)
        .background(message.role == "user" ? palette.highlight : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ToolRecordView: View {
    let tool: ToolExecution
    @Environment(\.nanoPalette) private var palette
    @State private var expanded = false
    @State private var showRaw = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    PhosphorIcon(icon: expanded ? .caretDown : .caretRight, size: 16)
                    PhosphorIcon(icon: .terminal, size: 16)
                    Text(tool.name).font(TrigramsFont.medium(13))
                    if let duration = tool.duration { Text(duration, format: .number.precision(.fractionLength(1))).font(TrigramsFont.body(12)); Text("s").font(TrigramsFont.body(12)) }
                    Spacer()
                    StatusBadge(status: tool.status)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(TrigramsButtonStyle())
            .accessibilityLabel("\(tool.name), \(tool.status.label)")
            .accessibilityValue(expanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
            .accessibilityIdentifier("toolRecord.\(tool.id)")
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Arguments").font(TrigramsFont.medium(12)).foregroundStyle(palette.secondary)
                    Text(tool.arguments.formatted).font(TrigramsFont.code()).textSelection(.enabled)
                    if !tool.output.isEmpty {
                        Text("Output").font(TrigramsFont.medium(12)).foregroundStyle(palette.secondary)
                        Text(tool.output).font(TrigramsFont.code()).textSelection(.enabled)
                            .foregroundStyle(tool.status == .error ? palette.errorText : palette.foreground)
                            .accessibilityIdentifier("toolOutput.\(tool.id)")
                    }
                    TrigramsButton(label: showRaw ? String(localized: "Hide complete result") : String(localized: "Show complete result"), icon: .more, identifier: "completeToolResult.\(tool.id)") { showRaw.toggle() }
                    if showRaw { Text(tool.result.formatted).font(TrigramsFont.code(12)).textSelection(.enabled).accessibilityIdentifier("rawToolResult.\(tool.id)") }
                }.padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .foregroundStyle(palette.foreground)
        .background(palette.highlight, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ThinkingRecord: View {
    let text: String
    @State private var expanded = false
    @Environment(\.nanoPalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrigramsButton(label: String(localized: "Thinking"), icon: expanded ? .caretDown : .caretRight) { expanded.toggle() }
            if expanded { Text(text).font(TrigramsFont.body(13)).foregroundStyle(palette.secondary).textSelection(.enabled) }
        }
    }
}
