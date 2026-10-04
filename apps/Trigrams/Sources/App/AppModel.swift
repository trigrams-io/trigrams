import AppKit
import Observation

/// A disposable projection of pi state. Session JSONL and the pi settings
/// manager remain the authoritative stores.
@Observable @MainActor
final class AppModel {
    enum Connection { case starting, ready, failed }
    enum SettingsTab: String, CaseIterable { case appearance, systemPrompt, skills }

    let runtime: any AppRuntimeServing
    var connection: Connection = .starting
    var sessions: [ChatSession] = []
    var selectedSession: ChatSession?
    var messages: [ChatMessage] = []
    var tools: [ToolExecution] = []
    var runStatus: RunStatus = .idle
    var composerText = ""
    var searchText = ""
    var queuedPrompts: [QueuedPrompt] = []
    var isLoading = false
    var isStopping = false
    var errorMessage: String?
    var modelName = "Apple On-Device"
    var modelAvailable = false
    var modelReason = String(localized: "Checking model availability…")
    var showModelDetails = false
    var sidebarVisible = true
    var settingsVisible = false
    var settingsTab: SettingsTab = .appearance
    var theme: AppTheme
    var systemPromptDraft = ""
    var savedSystemPrompt = ""
    var defaultSystemPrompt = ""
    var skillDirectories: [String] = []
    var disabledSkills: [String] = []
    var skills: [SkillResource] = []
    var resourceDiagnostics: [ResourceDiagnostic] = []
    var resourcesRevision = 0
    var settingsNotice: String?
    var branchVisible = false
    var branchEntries: [JSONValue] = []
    var branchLeafID: String?
    var dialog: ExtensionDialog?
    var extensionStatuses: [String: String] = [:]
    var extensionWidgets: [String: String] = [:]
    var extensionNotifications: [String] = []
    var compatibilityVisible = false
    var terminalFrames: [TerminalFrame] = []
    var terminalGeneration = 0

    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var lastSequence: [String: Int] = [:]
    @ObservationIgnored private var defaults: UserDefaults
    @ObservationIgnored private var pendingPath: String?
    @ObservationIgnored private var terminalSequence = 0
    @ObservationIgnored private var editorSync: Task<Void, Never>?

    init(runtime: any AppRuntimeServing, defaults: UserDefaults = .standard) {
        self.runtime = runtime
        self.defaults = defaults
        self.theme = AppTheme(rawValue: defaults.string(forKey: "appearance") ?? "system") ?? .system
        runtime.onNotification = { [weak self] method, params in self?.receive(method, params: params) }
    }

    var isWorking: Bool { runStatus == .working }
    var canSend: Bool { connection == .ready && modelAvailable && !isLoading && !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var displayedSystemPrompt: String { savedSystemPrompt.isEmpty ? defaultSystemPrompt : savedSystemPrompt }
    var promptHasChanges: Bool { systemPromptDraft != displayedSystemPrompt }
    var filteredSessions: [ChatSession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? sessions : sessions.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.cwd.localizedCaseInsensitiveContains(query) }
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        connection = .starting
        do {
            try await runtime.start()
            await loadSettings()
            await refreshSessions()
            if let session = sessions.first(where: { $0.id == selectedSession?.id }) ?? sessions.first { await open(session, restoring: true) }
            else { applySnapshot(try await runtime.request("session.create", params: [:])) }
            await reloadResources(reload: false)
            connection = .ready
        } catch {
            connection = .failed
            errorMessage = error.localizedDescription
        }
    }

    func retryStartup() async {
        runtime.stop()
        didStart = false
        errorMessage = nil
        await start()
    }

    func completeToolOutput(_ id: String) async -> JSONValue? {
        do {
            let value = try await runtime.request("tool.output", params: ["id": .string(id)])["result"]
            return value == .null ? nil : value
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func refreshSessions() async {
        do {
            let result = try await runtime.request("session.list", params: [:])
            sessions = (result["sessions"].array ?? []).compactMap(ChatSession.init)
        } catch { errorMessage = error.localizedDescription }
    }

    func newChat() async {
        guard connection == .ready, !isLoading, !isWorking else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await runtime.request("session.create", params: [:])
            applySnapshot(result)
            composerText = ""
            queuedPrompts = []
            errorMessage = nil
            await reloadResources(reload: false)
            await refreshSessions()
        } catch { errorMessage = error.localizedDescription }
    }

    func open(_ session: ChatSession, restoring: Bool = false) async {
        guard !isWorking, !isLoading else { return }
        guard restoring || session.id != selectedSession?.id else { return }
        pendingPath = session.path
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await runtime.request("session.open", params: ["path": .string(session.path)])
            guard pendingPath == session.path else { return }
            applySnapshot(result)
            queuedPrompts = []
            composerText = ""
            errorMessage = nil
            await reloadResources(reload: false)
        } catch { errorMessage = error.localizedDescription }
    }

    func submit(mode: String? = nil) async {
        guard canSend else { return }
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedSession == nil { await newChat() }
        guard selectedSession != nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            editorSync?.cancel()
            _ = try await runtime.request("ui.editor.set", params: ["text": .string(text)])
            var params: [String: JSONValue] = ["text": .string(text)]
            if let mode { params["mode"] = .string(mode) }
            let method = mode == "steer" ? "session.steer" : mode == "followUp" ? "session.followUp" : "session.prompt"
            let result = try await runtime.request(method, params: params)
            guard result["accepted"].bool != false else { return }
            composerText = ""
            if let mode { queuedPrompts.append(QueuedPrompt(text: text, mode: mode)) }
            else { runStatus = .working }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func stopGeneration() async {
        guard isWorking, !isStopping else { return }
        isStopping = true
        do { _ = try await runtime.request("session.abort", params: [:]) }
        catch {
            isStopping = false
            errorMessage = error.localizedDescription
        }
    }

    func loadSettings() async {
        do { applySettings(try await runtime.request("settings.get", params: [:])) }
        catch { errorMessage = error.localizedDescription }
    }

    func setTheme(_ value: AppTheme) async {
        theme = value
        defaults.set(value.rawValue, forKey: "appearance")
        _ = await updateSettings(["theme": .string(value.rawValue)])
    }

    func saveSystemPrompt() async {
        guard promptHasChanges else { return }
        if await updateSettings(["systemPrompt": .string(systemPromptDraft)]) {
            settingsNotice = String(localized: "System prompt saved")
        }
    }

    func resetSystemPrompt() async {
        if await updateSettings(["systemPrompt": .string("")]) {
            settingsNotice = String(localized: "Default system prompt restored")
        }
    }

    func chooseSkillDirectory() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = String(localized: "Choose a directory containing standard pi skills")
        panel.prompt = String(localized: "Add directory")
        guard await panel.begin() == .OK, let url = panel.url else { return }
        await addSkillDirectory(url.path)
    }

    func addSkillDirectory(_ path: String) async {
        guard !skillDirectories.contains(path) else { return }
        guard await updateSettings(["skillDirectories": .array((skillDirectories + [path]).map(JSONValue.string))]) else { return }
        await reloadResources()
    }

    func removeSkillDirectory(_ path: String) async {
        guard await updateSettings(["skillDirectories": .array(skillDirectories.filter { $0 != path }.map(JSONValue.string))]) else { return }
        await reloadResources()
    }

    func setSkill(_ skill: SkillResource, enabled: Bool) async {
        let updated = enabled ? disabledSkills.filter { $0 != skill.path && $0 != skill.name } : Array(Set(disabledSkills + [skill.path])).sorted()
        guard await updateSettings(["disabledSkills": .array(updated.map(JSONValue.string))]) else { return }
        await reloadResources()
    }

    func reloadResources(reload: Bool = true) async {
        do {
            if reload { _ = try await runtime.request("resources.reload", params: [:]) }
            let result = try await runtime.request("resources.list", params: [:])
            skills = (result["skills"].array ?? []).compactMap(SkillResource.init)
            resourceDiagnostics = (result["diagnostics"].array ?? []).enumerated().map { ResourceDiagnostic($0.element, index: $0.offset) }
            resourcesRevision += 1
            if reload { settingsNotice = String(localized: "Resources reloaded") }
        } catch { errorMessage = error.localizedDescription }
    }

    func showBranches() async {
        branchVisible = true
        do {
            let result = try await runtime.request("session.tree", params: [:])
            branchEntries = result["entries"].array ?? []
            branchLeafID = result["leafId"].string
        } catch { errorMessage = error.localizedDescription }
    }

    func fork(at entryID: String) async {
        guard !isWorking else { return }
        do {
            let result = try await runtime.request("session.fork", params: ["entryId": .string(entryID)])
            guard result["cancelled"].bool != true else { return }
            applySnapshot(result)
            branchVisible = false
            await refreshSessions()
        } catch { errorMessage = error.localizedDescription }
    }

    func reply(to dialog: ExtensionDialog, value: JSONValue = .null, cancelled: Bool = false) async {
        do {
            _ = try await runtime.request("ui.reply", params: ["id": .string(dialog.id), "value": value, "cancelled": .bool(cancelled)])
            if self.dialog?.id == dialog.id { self.dialog = nil }
        } catch { errorMessage = error.localizedDescription }
    }

    func sendCompatibilityInput(_ text: String) async {
        do { _ = try await runtime.request("ui.tui.input", params: ["data": .string(text)]) }
        catch { errorMessage = error.localizedDescription }
    }

    func resizeCompatibility(columns: Int, rows: Int) async {
        do { _ = try await runtime.request("ui.tui.resize", params: ["columns": .number(Double(columns)), "rows": .number(Double(rows))]) }
        catch { errorMessage = error.localizedDescription }
    }

    func closeCompatibility() async {
        do {
            _ = try await runtime.request("ui.tui.close", params: [:])
            compatibilityVisible = false
        } catch { errorMessage = error.localizedDescription }
    }

    func syncEditorText() {
        guard connection == .ready else { return }
        editorSync?.cancel()
        let text = composerText
        editorSync = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            do { _ = try await runtime.request("ui.editor.set", params: ["text": .string(text)]) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func updateSettings(_ values: [String: JSONValue]) async -> Bool {
        settingsNotice = nil
        do {
            applySettings(try await runtime.request("settings.update", params: values))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func applySettings(_ value: JSONValue) {
        savedSystemPrompt = value["systemPrompt"].string ?? ""
        defaultSystemPrompt = value["defaultSystemPrompt"].string ?? ""
        systemPromptDraft = displayedSystemPrompt
        skillDirectories = value["skillDirectories"].array?.compactMap(\.string) ?? []
        disabledSkills = value["disabledSkills"].array?.compactMap(\.string) ?? []
        if let raw = value["theme"].string, let theme = AppTheme(rawValue: raw) {
            self.theme = theme
            defaults.set(raw, forKey: "appearance")
        }
    }

    private func applySnapshot(_ value: JSONValue) {
        if let session = ChatSession(value["session"]) {
            if session.id != selectedSession?.id { tools = [] }
            selectedSession = session
            if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
            else { sessions.insert(session, at: 0) }
        }
        if let values = value["messages"].array {
            messages = values.enumerated().map { ChatMessage($0.element, index: $0.offset) }
            rebuildTools()
        }
        if let raw = value["status"].string, let status = RunStatus(rawValue: raw) {
            runStatus = status
            if status != .working {
                isStopping = false
                for index in tools.indices where tools[index].status == .working { tools[index].status = status == .error ? .error : .interrupted }
            }
        }
    }

    func receive(_ method: String, params: JSONValue) {
        switch method {
        case "runtime.availability":
            modelAvailable = params["available"].bool ?? false
            modelReason = params["reason"].string ?? ""
            modelName = params["model"].string ?? "Apple On-Device"
        case "session.snapshot":
            applySnapshot(params)
        case "session.event":
            let sessionID = params["sessionID"].string ?? selectedSession?.id ?? ""
            let key = "\(params["backendInstance"].string ?? "runtime").\(sessionID)"
            if let sequence = params["sequence"].int {
                guard sequence > (lastSequence[key] ?? -1) else { return }
                lastSequence[key] = sequence
            }
            guard sessionID == selectedSession?.id || selectedSession == nil else { return }
            receiveEvent(params["event"])
        case "resources.changed":
            Task { await reloadResources(reload: false) }
        case "ui.request": dialog = ExtensionDialog(params)
        case "ui.dismiss": if params["id"].string == dialog?.id { dialog = nil }
        case "ui.notify":
            if let message = params["message"].string { extensionNotifications.append(message) }
        case "ui.update": receiveUIUpdate(params)
        case "ui.tui.open":
            terminalGeneration += 1
            terminalFrames = []
            compatibilityVisible = true
        case "ui.tui.frame":
            terminalSequence += 1
            terminalFrames.append(TerminalFrame(id: terminalSequence, data: params["data"].string ?? ""))
            if terminalFrames.count > 1_024 { terminalFrames.removeFirst(terminalFrames.count - 1_024) }
        case "ui.tui.close": compatibilityVisible = false
        case "runtime.interrupted", "runtime.disconnected":
            editorSync?.cancel()
            runStatus = .interrupted
            connection = .failed
            isStopping = false
            errorMessage = params["message"].string ?? String(localized: "The runtime was interrupted. Your recorded results have been preserved.")
        case "runtime.error", "extension.error":
            errorMessage = params["message"].string ?? params["error"].string ?? params.formatted
        default: break
        }
    }

    private func receiveUIUpdate(_ value: JSONValue) {
        let method = value["method"].string ?? ""
        let key = value["key"].string ?? "default"
        switch method {
        case "setEditorText", "editor": composerText = value["text"].string ?? ""
        case "setStatus", "status": extensionStatuses[key] = value["text"].string
        case "setWidget", "widget": extensionWidgets[key] = value["text"].string ?? (value["lines"].array ?? value["content"].array)?.compactMap(\.string).joined(separator: "\n")
        default: break
        }
    }

    private func receiveEvent(_ event: JSONValue) {
        switch event["type"].string {
        case "agent_start": runStatus = .working
        case "agent_settled":
            runStatus = isStopping ? .stopped : .idle
            isStopping = false
            Task { await refreshSessions() }
        case "message_start", "message_update", "message_end":
            let raw = event["message"]
            guard raw != .null else { return }
            let message = ChatMessage(raw, index: messages.count)
            if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index] = message }
            else if event["type"].string == "message_update", messages.last?.role == message.role { messages[messages.count - 1] = message }
            else { messages.append(message) }
            if message.role == "user", let index = queuedPrompts.firstIndex(where: { $0.text == message.text }) { queuedPrompts.remove(at: index) }
            rebuildTools()
        case "tool_execution_start":
            let id = event["toolCallId"].string ?? UUID().uuidString
            let tool = ToolExecution(id: id, name: event["toolName"].string ?? "", arguments: event["args"])
            if let index = tools.firstIndex(where: { $0.id == id }) { tools[index] = tool }
            else { tools.append(tool) }
        case "tool_execution_update", "tool_execution_end":
            guard let id = event["toolCallId"].string, let index = tools.firstIndex(where: { $0.id == id }) else { return }
            tools[index].result = event["result"] == .null ? event["partialResult"] : event["result"]
            if event["type"].string == "tool_execution_end" {
                tools[index].status = event["isError"].bool == true ? .error : .idle
                tools[index].duration = Date.now.timeIntervalSince(tools[index].startedAt)
            }
        case "auto_compaction_start": extensionStatuses["compaction"] = String(localized: "Compacting context")
        case "auto_compaction_end": extensionStatuses.removeValue(forKey: "compaction")
        case "auto_retry_start": extensionStatuses["retry"] = event["errorMessage"].string ?? String(localized: "Retrying")
        case "auto_retry_end": extensionStatuses.removeValue(forKey: "retry")
        default: break
        }
    }

    private func rebuildTools() {
        for message in messages {
            for call in message.toolCalls {
                guard let id = call["id"].string, !tools.contains(where: { $0.id == id }) else { continue }
                tools.append(ToolExecution(id: id, name: call["name"].string ?? "", arguments: call["arguments"]))
            }
            if let id = message.toolCallID, let index = tools.firstIndex(where: { $0.id == id }) {
                tools[index].result = message.raw
                tools[index].status = message.isError ? .error : .idle
            }
        }
    }
}
