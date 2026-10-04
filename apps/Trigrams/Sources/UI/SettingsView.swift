import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.nanoPalette) private var palette
    var body: some View {
        GeometryReader { geometry in
            panel(height: min(760, geometry.size.height - 48))
                .frame(width: min(1000, geometry.size.width - 64), height: min(760, geometry.size.height - 48))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func panel(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(TrigramsFont.medium(20)).foregroundStyle(palette.strong)
                Spacer()
                IconButton(icon: .close, label: String(localized: "Close settings"), identifier: "closeSettingsButton") { model.settingsVisible = false }
            }.padding(24)
            DividerLine()
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    tab(.appearance, label: String(localized: "Appearance"), icon: .sun)
                    tab(.systemPrompt, label: String(localized: "System prompt"), icon: .chats)
                    tab(.skills, label: String(localized: "Skills"), icon: .book)
                    Spacer()
                }.padding(12).frame(width: 180).frame(maxHeight: .infinity).background(palette.highlight)
                Rectangle().fill(palette.subtle).frame(width: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch model.settingsTab {
                        case .appearance: appearance
                        case .systemPrompt: systemPrompt(height: max(160, height - 275))
                        case .skills: skills
                        }
                        if let notice = model.settingsNotice {
                            HStack(spacing: 8) { PhosphorIcon(icon: .check, size: 16); Text(notice).font(TrigramsFont.body(13)) }
                                .foregroundStyle(palette.successText).accessibilityIdentifier("settingsNotice")
                        }
                    }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
                }.scrollIndicators(.hidden)
            }
        }
        .foregroundStyle(palette.foreground)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(palette.subtle, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settingsPanel")
    }

    private func tab(_ tab: AppModel.SettingsTab, label: String, icon: Phosphor) -> some View {
        Button {
            model.settingsTab = tab
            model.settingsNotice = nil
        } label: {
            HStack(spacing: 8) { PhosphorIcon(icon: icon, size: 16); Text(label); Spacer(minLength: 0) }
                .frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(TrigramsButtonStyle(variant: model.settingsTab == tab ? .selected : .plain))
            .accessibilityIdentifier("settingsTab.\(tab.rawValue)")
            .accessibilityValue(model.settingsTab == tab ? String(localized: "Selected") : String(localized: "Unselected"))
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Theme").font(TrigramsFont.medium(16))
            Text("Choose Nano Light, Nano Dark, or follow the appearance of macOS.")
                .font(TrigramsFont.body(14)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                ForEach(AppTheme.allCases) { theme in
                    Button { Task { await model.setTheme(theme) } } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            ThemePreview(theme: theme).frame(height: 100)
                            HStack {
                                Text(theme.label).font(TrigramsFont.medium(13))
                                Spacer()
                                if model.theme == theme { PhosphorIcon(icon: .check, size: 16).foregroundStyle(palette.accentText) }
                            }
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TrigramsButtonStyle())
                    .background(palette.highlight, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(model.theme == theme ? palette.salient : palette.subtle, lineWidth: model.theme == theme ? 2 : 1) }
                    .accessibilityLabel(theme.label)
                    .accessibilityValue(model.theme == theme ? String(localized: "Selected") : String(localized: "Unselected"))
                    .accessibilityIdentifier("theme.\(theme.rawValue)")
                }
            }
            Text("System changes automatically when macOS switches between light and dark appearance.")
                .font(TrigramsFont.body(12)).foregroundStyle(palette.secondary)
        }
    }

    private func systemPrompt(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("System prompt").font(TrigramsFont.medium(16))
            Text("Keep your instructions concise. Skills and project context are added automatically.")
                .font(TrigramsFont.body(14)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            PromptEditor(text: $model.systemPromptDraft, height: height)
            HStack {
                TrigramsButton(label: String(localized: "Reset to default"), icon: .reload, variant: .outlined, identifier: "resetSystemPromptButton") { Task { await model.resetSystemPrompt() } }
                Spacer()
                TrigramsButton(label: String(localized: "Save"), variant: .primary, identifier: "saveSystemPromptButton") { Task { await model.saveSystemPrompt() } }
                    .disabled(!model.promptHasChanges || model.connection != .ready)
            }
        }
    }

    private var skills: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Skills").font(TrigramsFont.medium(16))
                    Text("Standard pi skills, with their source and loading diagnostics.")
                        .font(TrigramsFont.body(13)).foregroundStyle(palette.secondary)
                }
                Spacer()
                IconButton(icon: .reload, label: String(localized: "Reload resources"), identifier: "reloadResourcesButton") { Task { await model.reloadResources() } }
            }
            Text("Skill directories").font(TrigramsFont.medium(13))
            ForEach(model.skillDirectories, id: \.self) { path in
                HStack(spacing: 8) {
                    PhosphorIcon(icon: .folder).foregroundStyle(palette.secondary)
                    Text(path).font(TrigramsFont.body(12)).textSelection(.enabled).lineLimit(2)
                    Spacer()
                    IconButton(icon: .close, label: String(localized: "Remove directory"), identifier: "removeSkillDirectory.\(path)") { Task { await model.removeSkillDirectory(path) } }
                }.padding(.vertical, 4)
            }
            TrigramsButton(label: String(localized: "Add directory"), icon: .plus, variant: .outlined, identifier: "addSkillDirectoryButton") { Task { await model.chooseSkillDirectory() } }
            DividerLine()
            if model.skills.isEmpty {
                Text("No skills loaded. Add a directory containing SKILL.md resources.")
                    .font(TrigramsFont.body(13)).foregroundStyle(palette.secondary)
            }
            ForEach(model.skills) { skill in
                SkillRow(skill: skill) { enabled in Task { await model.setSkill(skill, enabled: enabled) } }
                DividerLine()
            }
            if !model.resourceDiagnostics.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Resource diagnostics").font(TrigramsFont.medium(14))
                    ForEach(model.resourceDiagnostics) { diagnostic in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                PhosphorIcon(icon: .warning, size: 16)
                                Text(diagnostic.message).font(TrigramsFont.body(13)).textSelection(.enabled)
                            }.foregroundStyle(palette.warningText)
                            if !diagnostic.path.isEmpty { Text(diagnostic.path).font(TrigramsFont.code(11)).textSelection(.enabled) }
                            if !diagnostic.source.isEmpty { Text(diagnostic.source).font(TrigramsFont.body(12)).foregroundStyle(palette.secondary) }
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(palette.highlight, in: RoundedRectangle(cornerRadius: 8))
                    }
                }.accessibilityIdentifier("resourceDiagnostics")
            }
        }
    }
}

private struct PromptEditor: View {
    @Binding var text: String
    let height: CGFloat
    @State private var focused = false
    var body: some View {
        FieldSurface(focused: focused) {
            NativeTextEditor(text: $text, identifier: "systemPromptEditor", placeholder: String(localized: "System prompt"), onFocus: { focused = $0 })
                .frame(height: height)
        }
    }
}

private struct ThemePreview: View {
    let theme: AppTheme
    @Environment(\.nanoPalette) private var currentPalette
    var body: some View {
        let palette = NanoPalette(isDark: theme == .dark || theme == .system && currentPalette.isDark)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Rectangle().fill(palette.salient).frame(width: 18, height: 3)
                Rectangle().fill(palette.secondary).frame(width: 23, height: 3)
                Rectangle().fill(palette.secondary).frame(width: 20, height: 3)
                Spacer()
            }.padding(10).frame(width: 42).background(palette.highlight)
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(palette.foreground).frame(width: 42, height: 3)
                Rectangle().fill(palette.secondary).frame(height: 3)
                Rectangle().fill(palette.secondary).frame(width: 35, height: 3)
                Spacer()
                RoundedRectangle(cornerRadius: 3).stroke(palette.secondary, lineWidth: 1).frame(height: 16)
            }.padding(10).frame(maxWidth: .infinity).background(palette.background)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }
}

private struct SkillRow: View {
    let skill: SkillResource
    let onToggle: (Bool) -> Void
    @Environment(\.nanoPalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                PhosphorIcon(icon: .book).foregroundStyle(palette.accentText)
                Text(skill.name).font(TrigramsFont.medium(14)).textSelection(.enabled)
                Spacer()
                CustomToggle(label: "\(skill.name) \(String(localized: "skill"))", isOn: skill.enabled, identifier: "skillToggle.\(skill.name)") { onToggle(!skill.enabled) }
            }
            Text(skill.description).font(TrigramsFont.body(13)).foregroundStyle(palette.secondary).textSelection(.enabled)
            HStack(alignment: .top, spacing: 8) {
                Text(skill.source).font(TrigramsFont.medium(11)).foregroundStyle(palette.secondary)
                Text(skill.path).font(TrigramsFont.code(11)).foregroundStyle(palette.secondary).textSelection(.enabled)
            }
        }
        .padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("skillRow.\(skill.name)")
    }
}
