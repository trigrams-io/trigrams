import SwiftUI

struct ExtensionDialogCard: View {
    let dialog: ExtensionDialog
    @Bindable var model: AppModel
    @Environment(\.nanoPalette) private var palette
    @State private var input = ""
    @State private var focused = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PhosphorIcon(icon: .chats).foregroundStyle(palette.accentText)
                Text(dialog.title).font(TrigramsFont.medium(18)).foregroundStyle(palette.strong)
                Spacer()
            }
            if !dialog.message.isEmpty { Text(dialog.message).font(TrigramsFont.body(14)).textSelection(.enabled) }
            if dialog.method == "select" {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(dialog.options, id: \.self) { option in
                            Button { Task { await model.reply(to: dialog, value: .string(option)) } } label: {
                                HStack { Text(option).font(TrigramsFont.body(14)); Spacer(); PhosphorIcon(icon: .caretRight, size: 16) }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(TrigramsButtonStyle(variant: .outlined))
                            .accessibilityLabel(option).accessibilityIdentifier("dialogOption.\(option)")
                        }
                    }
                }.scrollIndicators(.hidden).frame(maxHeight: 260)
            } else if dialog.method == "input" || dialog.method == "editor" {
                FieldSurface(focused: focused) {
                    NativeTextEditor(text: $input, identifier: "dialogInput", placeholder: dialog.placeholder, isComposer: dialog.method == "input", onSubmit: { Task { await model.reply(to: dialog, value: .string(input)) } }, onFocus: { focused = $0 })
                        .frame(height: dialog.method == "editor" ? 220 : 55)
                }
            }
            HStack {
                TrigramsButton(label: String(localized: "Cancel"), variant: .outlined, identifier: "dialogCancelButton") {
                    Task { await model.reply(to: dialog, value: isConfirmation ? .bool(false) : .null, cancelled: !isConfirmation) }
                }.keyboardShortcut(.escape, modifiers: [])
                Spacer()
                if isConfirmation {
                    TrigramsButton(label: dialog.method == "projectTrust" ? String(localized: "Trust project") : String(localized: "Confirm"), variant: .primary, identifier: "dialogAcceptButton") { Task { await model.reply(to: dialog, value: .bool(true)) } }
                } else if dialog.method != "select" {
                    TrigramsButton(label: String(localized: "Submit"), variant: .primary, identifier: "dialogSubmitButton") { Task { await model.reply(to: dialog, value: .string(input)) } }
                }
            }
        }
        .padding(24).frame(width: 560, alignment: .leading)
        .foregroundStyle(palette.foreground)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(palette.inputBorder, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("extensionDialog")
        .onAppear { input = dialog.prefill }
    }
    private var isConfirmation: Bool { dialog.method == "confirm" || dialog.method == "projectTrust" }
}

struct BranchCard: View {
    @Bindable var model: AppModel
    @State private var selectedEntryID: String?
    @Environment(\.nanoPalette) private var palette
    var body: some View {
        GeometryReader { geometry in
            panel.frame(width: min(800, geometry.size.width - 64), height: min(640, geometry.size.height - 64))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private var panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Branches").font(TrigramsFont.medium(20)).foregroundStyle(palette.strong)
                Spacer()
                IconButton(icon: .close, label: String(localized: "Close branches"), identifier: "closeBranchesButton") { model.branchVisible = false }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            Text("Select a recorded entry to fork a new conversation. The original session remains available.")
                .font(TrigramsFont.body(13)).foregroundStyle(palette.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.branchEntries.enumerated()), id: \.offset) { index, entry in
                        if let id = entry["id"].string {
                            let label = entryLabel(entry, index: index)
                            Button { selectedEntryID = id } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    PhosphorIcon(icon: .branch, size: 16).padding(.top, 1)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(label).font(TrigramsFont.body(13)).lineLimit(3).multilineTextAlignment(.leading)
                                        if id == model.branchLeafID { Text("Current branch").font(TrigramsFont.body(11)).foregroundStyle(palette.secondary) }
                                    }
                                    Spacer()
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(TrigramsButtonStyle(variant: selectedEntryID == id ? .selected : .plain))
                            .accessibilityLabel(label)
                            .accessibilityValue(selectedEntryID == id ? String(localized: "Selected") : String(localized: "Unselected"))
                            .accessibilityIdentifier("branchEntry.\(id)")
                        }
                    }
                    if model.branchEntries.isEmpty { Text("No recorded entries yet").font(TrigramsFont.body(13)).foregroundStyle(palette.secondary) }
                }
            }.scrollIndicators(.hidden).frame(maxHeight: .infinity)
            HStack {
                Spacer()
                TrigramsButton(label: String(localized: "Fork conversation"), icon: .branch, variant: .primary, identifier: "forkBranchButton") {
                    if let selectedEntryID { Task { await model.fork(at: selectedEntryID) } }
                }.disabled(selectedEntryID == nil || model.isWorking)
            }
        }
        .padding(24)
        .foregroundStyle(palette.foreground)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(palette.inputBorder, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("branchesPanel")
    }
    private func entryLabel(_ entry: JSONValue, index: Int) -> String {
        if entry["type"].string == "message" {
            let message = ChatMessage(entry["message"], index: index)
            return "\(message.label): \(message.text.isEmpty ? message.raw.formatted : message.text)"
        }
        if let summary = entry["summary"].string { return "\(entry["type"].string ?? ""): \(summary)" }
        return entry["type"].string ?? String(localized: "Session entry")
    }
}

struct CompatibilityPanel: View {
    @Bindable var model: AppModel
    @Environment(\.nanoPalette) private var palette
    var body: some View {
        GeometryReader { geometry in
            panel.frame(width: min(1100, geometry.size.width - 64), height: min(800, geometry.size.height - 64))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                PhosphorIcon(icon: .terminal)
                Text("Extension interface").font(TrigramsFont.medium(15))
                Spacer()
                IconButton(icon: .close, label: String(localized: "Close extension interface"), identifier: "closeCompatibilityButton") { Task { await model.closeCompatibility() } }
            }.padding(12)
            DividerLine()
            CompatibilityTerminal(frames: model.terminalFrames, generation: model.terminalGeneration, onInput: { data in Task { await model.sendCompatibilityInput(data) } }, onResize: { columns, rows in Task { await model.resizeCompatibility(columns: columns, rows: rows) } })
                .padding(12)
        }
        .foregroundStyle(palette.foreground)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(palette.inputBorder, lineWidth: 1) }
    }
}
