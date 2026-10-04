import Foundation
import FoundationModels

struct InferenceFailure: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { message }
}

/// Inference only. No executable `Tool` is ever registered with Apple's session.
/// The pi session remains the owner of history and of every tool execution.
@MainActor
final class FoundationModelService {
    private let testing: Bool
    private let forceUnavailable: Bool

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG
        testing = arguments.contains("--ui-testing")
        forceUnavailable = arguments.contains("--ui-testing-unavailable")
        #else
        testing = false
        forceUnavailable = false
        #endif
    }

    var availability: JSONValue {
        if forceUnavailable { return status(false, "The on-device model is unavailable in this test.") }
        if testing { return status(true, "Deterministic inference for UI testing") }
        switch SystemLanguageModel.default.availability {
        case .available: return status(true, "Available on this device")
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return status(false, "This Mac does not support Apple Intelligence.")
            case .appleIntelligenceNotEnabled: return status(false, "Enable Apple Intelligence in System Settings.")
            case .modelNotReady: return status(false, "The on-device model is still downloading or preparing.")
            @unknown default: return status(false, "The on-device model is unavailable.")
            }
        }
    }

    func generate(_ request: JSONValue, delta: (String) async throws -> Void) async throws -> JSONValue {
        guard availability["available"].bool == true else {
            throw InferenceFailure(code: "model.unavailable", message: availability["reason"].string ?? "Model unavailable")
        }
        let schema = try ActionSchema.make(tools: request["tools"].array ?? [])
        #if DEBUG
        if testing { return try await deterministicResponse(request, delta: delta) }
        #endif
        // A fresh session avoids duplicating the history maintained by pi.
        let session = LanguageModelSession(instructions: request["instructions"].string ?? "")
        #if compiler(>=6.4)
        let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: request["maxTokens"].int ?? 768)
        #else
        let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: request["maxTokens"].int ?? 768)
        #endif
        let stream = session.streamResponse(to: request["prompt"].string ?? "", schema: schema, options: options)
        var final: JSONValue = .null
        var text = ""
        for try await snapshot in stream {
            try Task.checkCancellation()
            final = try JSONDecoder().decode(JSONValue.self, from: Data(snapshot.content.jsonString.utf8))
            let current = final["text"].string ?? ""
            if current.hasPrefix(text), current != text {
                try await delta(String(current.dropFirst(text.count)))
                text = current
            }
        }
        guard final.object != nil, final["text"].string != nil else {
            throw InferenceFailure(code: "schema.response", message: "The model did not produce a complete action.")
        }
        return .object(["text": final["text"], "toolCalls": final["toolCalls"].array.map(JSONValue.array) ?? .array([])])
    }

    private func status(_ available: Bool, _ reason: String) -> JSONValue {
        .object(["available": .bool(available), "reason": .string(reason), "model": .string("Apple On-Device")])
    }

    #if DEBUG
    private func deterministicResponse(_ request: JSONValue, delta: (String) async throws -> Void) async throws -> JSONValue {
        let prompt = request["prompt"].string ?? ""
        let messages = (try? JSONDecoder().decode(JSONValue.self, from: Data(prompt.utf8)))?.array ?? []
        let lastUser = messages.lastIndex { $0["role"].string == "user" }
        let user = lastUser.map { messages[$0] } ?? .null
        let userText = user["content"].string ?? user["content"].array?.compactMap { $0["text"].string }.joined(separator: "\n") ?? prompt
        // This fixture replaces inference, never the pi tools or persistence.
        if userText.contains("[slow]") { try await Task.sleep(for: .seconds(8)) }
        if let range = userText.range(of: "[read:"), let end = userText[range.upperBound...].firstIndex(of: "]"),
           request["tools"].array?.contains(where: { $0["name"].string == "read" }) == true {
            let results = lastUser.map { messages.dropFirst($0 + 1).filter { $0["role"].string == "toolResult" } } ?? []
            if results.isEmpty {
                let path = String(userText[range.upperBound..<end])
                return .object(["text": .string(""), "toolCalls": .array([.object(["name": .string("read"), "arguments": .object(["path": .string(path)])])])])
            }
            let content = results.last?["content"].array?.compactMap { $0["text"].string }.joined(separator: "\n") ?? ""
            let response = "Read file: \(content)"
            try await delta(response)
            return .object(["text": .string(response), "toolCalls": .array([])])
        }
        let response = userText.contains("[markdown]") ? """
        A formatted reply.

        ## Details

        | Action | Result |
        | --- | --- |
        | Read | Completed |

        - Keep the user's scope.
        - Verify the result.

        ```swift
        let answer = 42
        ```

        [Trigrams source](https://github.com/trigrams-io/trigrams)
        """ : "Trigrams completed the request."
        try await delta(response)
        return .object(["text": .string(response), "toolCalls": .array([])])
    }
    #endif
}

/// Translate only supported JSON Schema constraints. Unsupported constraints
/// fail explicitly; the sidecar also validates against the original schema.
enum ActionSchema {
    static func make(tools: [JSONValue]) throws -> GenerationSchema {
        var properties: [DynamicGenerationSchema.Property] = [
            .init(name: "text", description: "Answer the user, or briefly describe the pending tool calls.", schema: .init(type: String.self))
        ]
        if !tools.isEmpty {
            let calls = try tools.enumerated().map { index, tool in
                guard let name = tool["name"].string else { throw unsupported("A tool is missing its name.") }
                return DynamicGenerationSchema(name: "ToolCall\(index)", description: tool["description"].string, properties: [
                    .init(name: "name", schema: .init(name: "ToolName\(index)", anyOf: [name])),
                    .init(name: "arguments", schema: try convert(tool["parameters"], name: "Arguments\(index)"))
                ])
            }
            let choice = DynamicGenerationSchema(name: "ToolCall", anyOf: calls)
            properties.append(.init(name: "toolCalls", description: "Only use tools when needed. Return an empty array for a final answer.", schema: .init(arrayOf: choice, maximumElements: 8), isOptional: true))
        }
        return try GenerationSchema(root: .init(name: "AgentAction", properties: properties), dependencies: [])
    }

    private static func convert(_ value: JSONValue, name: String) throws -> DynamicGenerationSchema {
        guard let schema = value.object else { throw unsupported("\(name) is not an object schema.") }
        let metadata: Set<String> = ["title", "description", "$schema", "$id", "$comment", "default", "examples", "deprecated", "readOnly", "writeOnly"]
        let supported: Set<String> = ["type", "properties", "required", "additionalProperties", "items", "minItems", "maxItems", "enum", "const", "anyOf", "minimum", "maximum"]
        let unknown = Set(schema.keys).subtracting(metadata.union(supported))
        guard unknown.isEmpty else { throw unsupported("\(name) uses unsupported constraints: \(unknown.sorted().joined(separator: ", ")).") }
        if let choices = schema["anyOf"]?.array {
            return .init(name: name, anyOf: try choices.enumerated().map { try convert($0.element, name: "\(name)Choice\($0.offset)") })
        }
        if let values = schema["enum"]?.array ?? schema["const"].map({ [$0] }) {
            let strings = values.compactMap(\.string)
            guard !strings.isEmpty, strings.count == values.count else { throw unsupported("\(name) requires a nonempty string enum.") }
            return .init(name: name, anyOf: strings)
        }
        switch schema["type"]?.string {
        case "object":
            if let additional = schema["additionalProperties"], additional != .bool(false) {
                throw unsupported("\(name) has dynamic additional properties.")
            }
            let required = Set(schema["required"]?.array?.compactMap(\.string) ?? [])
            let fields = schema["properties"]?.object ?? [:]
            guard required.isSubset(of: Set(fields.keys)) else { throw unsupported("\(name) requires undeclared fields.") }
            let properties = try fields.keys.sorted().map { key in
                DynamicGenerationSchema.Property(name: key, description: fields[key]?["description"].string, schema: try convert(fields[key] ?? .null, name: "\(name)_\(key)"), isOptional: !required.contains(key))
            }
            return .init(name: name, description: schema["description"]?.string, properties: properties)
        case "array":
            return .init(arrayOf: try convert(schema["items"] ?? .null, name: "\(name)Item"), minimumElements: schema["minItems"]?.int, maximumElements: schema["maxItems"]?.int)
        case "string": return .init(type: String.self)
        case "boolean": return .init(type: Bool.self)
        case "integer":
            var guides: [GenerationGuide<Int>] = []
            if let bound = schema["minimum"]?.int { guides.append(.minimum(bound)) }
            if let bound = schema["maximum"]?.int { guides.append(.maximum(bound)) }
            return .init(type: Int.self, guides: guides)
        case "number":
            var guides: [GenerationGuide<Double>] = []
            if let bound = schema["minimum"]?.number { guides.append(.minimum(bound)) }
            if let bound = schema["maximum"]?.number { guides.append(.maximum(bound)) }
            return .init(type: Double.self, guides: guides)
        default: throw unsupported("\(name) has an unsupported or missing type.")
        }
    }

    private static func unsupported(_ message: String) -> InferenceFailure {
        InferenceFailure(code: "schema.unsupported", message: message)
    }
}
