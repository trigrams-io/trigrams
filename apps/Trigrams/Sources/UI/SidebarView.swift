import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel
    @Environment(\.nanoPalette) private var palette
    @FocusState private var searchFocused: Bool
    @State private var searchVisible = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { Task { await model.newChat() } } label: {
                HStack(spacing: 10) {
                    PhosphorIcon(icon: .chats, size: 18)
                    Text("New chat").font(TrigramsFont.medium(13))
                    Spacer()
                    PhosphorIcon(icon: .plus, size: 16)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
                .buttonStyle(TrigramsButtonStyle())
                .foregroundStyle(palette.accentText)
                .background(palette.salient.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("newChatButton")
                .disabled(model.connection != .ready || model.isLoading || model.isWorking)
                .keyboardShortcut("n", modifiers: .command)
                .padding(.top, 16)
            HStack {
                Text("Chats").font(TrigramsFont.medium(12)).foregroundStyle(palette.secondary)
                Spacer()
                IconButton(icon: .magnifyingGlass, label: String(localized: "Search chats"), identifier: "chatSearchButton") {
                    searchVisible.toggle()
                    searchFocused = searchVisible
                    if !searchVisible { model.searchText = "" }
                }
            }
            if searchVisible {
                FieldSurface(focused: searchFocused) {
                    TextField(String(localized: "Search chats"), text: $model.searchText)
                        .textFieldStyle(.plain).font(TrigramsFont.body(13)).focused($searchFocused)
                        .accessibilityIdentifier("chatSearchField")
                        .onExitCommand { searchVisible = false; model.searchText = "" }
                }
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.filteredSessions) { session in
                        ChatRow(session: session, selected: model.selectedSession?.id == session.id, working: model.selectedSession?.id == session.id && model.isWorking) {
                            Task { await model.open(session) }
                        }
                        .disabled(model.isLoading || model.isWorking)
                    }
                    if model.filteredSessions.isEmpty {
                        Text(model.searchText.isEmpty ? String(localized: "Your conversations appear here") : String(localized: "No matching chats"))
                            .font(TrigramsFont.body(12)).foregroundStyle(palette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                    }
                }
            }.scrollIndicators(.hidden)
            Spacer(minLength: 0)
            DividerLine()
            VStack(alignment: .leading, spacing: 4) {
                TrigramsButton(label: String(localized: "Skills"), icon: .book, identifier: "skillsButton") {
                    model.settingsTab = .skills
                    model.settingsVisible = true
                }
                TrigramsButton(label: String(localized: "Settings"), icon: .settings, identifier: "settingsButton") {
                    model.settingsTab = .appearance
                    model.settingsVisible = true
                }.keyboardShortcut(",", modifiers: .command)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.highlight)
    }
}

struct ChatRow: View {
    let session: ChatSession
    let selected: Bool
    let working: Bool
    let action: () -> Void
    @Environment(\.nanoPalette) private var palette
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(session.title).font(TrigramsFont.medium(13)).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if working { PhosphorIcon(icon: .reload, size: 14).foregroundStyle(palette.salient) }
                }
                if let date = session.updatedAt {
                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(TrigramsFont.body(11)).foregroundStyle(palette.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(TrigramsButtonStyle(variant: selected ? .selected : .plain))
        .accessibilityLabel(session.title)
        .accessibilityValue(working ? String(localized: "Working") : selected ? String(localized: "Selected") : "")
        .accessibilityIdentifier("chatRow.\(session.id)")
    }
}
