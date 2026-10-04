import Foundation

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Nano Light")
        case .dark: String(localized: "Nano Dark")
        }
    }
}

enum RunStatus: String {
    case idle, working, stopped, error, interrupted
    var label: String {
        switch self {
        case .idle: String(localized: "Completed")
        case .working: String(localized: "Working")
        case .stopped: String(localized: "Stopped")
        case .error: String(localized: "Action failed")
        case .interrupted: String(localized: "Interrupted")
        }
    }
}

struct ChatSession: Identifiable, Equatable {
    let id: String
    let path: String
    var title: String
    let cwd: String
    let updatedAt: Date?

    init?(_ value: JSONValue) {
        guard let id = value["id"].string, let path = value["path"].string else { return nil }
        self.id = id
        self.path = path
        self.title = value["title"].string?.nilIfEmpty ?? String(localized: "New chat")
        self.cwd = value["cwd"].string ?? ""
        if let string = value["updatedAt"].string {
            self.updatedAt = ISO8601DateFormatter().date(from: string)
        } else if let milliseconds = value["updatedAt"].number {
            self.updatedAt = Date(timeIntervalSince1970: milliseconds / 1_000)
        } else { self.updatedAt = nil }
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let role: String
    let raw: JSONValue
    let text: String
    let thinking: String
    let toolCalls: [JSONValue]
    let toolCallID: String?
    let toolName: String?
    let isError: Bool

    init(_ value: JSONValue, index: Int) {
        self.raw = value
        self.role = value["role"].string ?? value["customType"].string ?? "extension"
        self.id = value["id"].string ?? "\(role).\(value["timestamp"].number.map { String($0) } ?? String(index))"
        let content = value["content"]
        let blocks = content.array ?? []
        self.text = content.string ?? blocks.compactMap { block in
            if block["type"].string == "text" { return block["text"].string }
            if block["type"].string == "image" { return String(localized: "Image attachment") }
            return nil
        }.joined(separator: "\n")
        self.thinking = blocks.filter { $0["type"].string == "thinking" }.compactMap { $0["thinking"].string }.joined(separator: "\n")
        self.toolCalls = blocks.filter { $0["type"].string == "toolCall" }
        self.toolCallID = value["toolCallId"].string
        self.toolName = value["toolName"].string
        self.isError = value["isError"].bool ?? false
    }

    var label: String {
        switch role {
        case "user": String(localized: "You")
        case "assistant": String(localized: "Trigrams")
        case "toolResult": toolName ?? String(localized: "Tool result")
        case "custom": raw["customType"].string ?? String(localized: "Extension message")
        default: role
        }
    }
}

struct ToolExecution: Identifiable, Equatable {
    let id: String
    var name: String
    var arguments: JSONValue
    var result: JSONValue = .null
    var status: RunStatus = .working
    var startedAt: Date = .now
    var duration: TimeInterval?

    var output: String {
        let content = result["content"].array
        if let content {
            return content.compactMap { $0["text"].string }.joined(separator: "\n")
        }
        return result == .null ? "" : result.formatted
    }
}

struct SkillResource: Identifiable, Equatable {
    var id: String { path }
    let name: String
    let description: String
    let path: String
    let enabled: Bool
    let source: String

    init?(_ value: JSONValue) {
        guard let name = value["name"].string, let path = value["path"].string else { return nil }
        self.name = name
        self.description = value["description"].string ?? ""
        self.path = path
        self.enabled = value["enabled"].bool ?? true
        self.source = value["source"].string ?? String(localized: "Local")
    }
}

struct ResourceDiagnostic: Identifiable, Equatable {
    let id: String
    let message: String
    let path: String
    let source: String

    init(_ value: JSONValue, index: Int) {
        self.id = "diagnostic.\(index)"
        self.message = value["message"].string ?? value.string ?? value.formatted
        self.path = value["path"].string ?? ""
        self.source = value["source"].string ?? value["type"].string ?? ""
    }
}

struct QueuedPrompt: Identifiable, Equatable {
    let id = UUID().uuidString
    let text: String
    let mode: String
    var label: String { mode == "steer" ? String(localized: "Steer now") : String(localized: "Queue after completion") }
}

struct ExtensionDialog: Identifiable {
    let id: String
    let method: String
    let title: String
    let message: String
    let options: [String]
    let placeholder: String
    let prefill: String

    init?(_ value: JSONValue) {
        guard let id = value["id"].string, let method = value["method"].string else { return nil }
        self.id = id
        self.method = method
        self.title = value["title"].string ?? String(localized: "Your input is needed")
        self.message = value["message"].string ?? ""
        self.options = value["options"].array?.compactMap(\.string) ?? []
        self.placeholder = value["placeholder"].string ?? ""
        self.prefill = value["prefill"].string ?? ""
    }
}

struct TerminalFrame: Identifiable, Equatable {
    let id: Int
    let data: String
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
