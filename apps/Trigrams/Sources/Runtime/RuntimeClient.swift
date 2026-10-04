import Foundation
import Network

struct RuntimeFailure: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { message }
}

/// Owns the bundled sidecar and authenticated local transport. All UI state
/// stays on the main actor; Network callbacks only deliver immutable bytes.
@MainActor
final class RuntimeClient: AppRuntimeServing {
    var onNotification: ((String, JSONValue) -> Void)?
    private let inference: FoundationModelService
    private let arguments: [String]
    private let queue = DispatchQueue(label: "io.trigrams.transport")
    private var process: Process?
    private var connection: NWConnection?
    private var connecting: CheckedContinuation<Void, any Error>?
    private var pending: [String: CheckedContinuation<JSONValue, any Error>] = [:]
    private var deadlines: [String: Task<Void, Never>] = [:]
    private var generations: [String: Task<Void, Never>] = [:]
    private var buffer = Data()
    private var runtimeDirectory: URL?
    private var logHandle: FileHandle?
    private let frameLimit = 4 * 1024 * 1024

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.arguments = arguments
        inference = FoundationModelService(arguments: arguments)
    }

    func start() async throws {
        guard process == nil else { return }
        do {
            let manager = FileManager.default
            let dataDirectory = try dataDirectoryURL()
            try manager.createDirectory(at: dataDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let runtime = runtimeBaseDirectory().appendingPathComponent("trigrams-\(UUID().uuidString.prefix(8))", isDirectory: true)
            try manager.createDirectory(at: runtime, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            runtimeDirectory = runtime
            let socket = runtime.appendingPathComponent("agent.sock").path
            guard socket.utf8.count < 104 else { throw RuntimeFailure(code: "transport.path", message: "The runtime socket path is too long.") }
            let token = UUID().uuidString + UUID().uuidString
            let resources = Bundle.main.resourceURL!.appendingPathComponent("runtime", isDirectory: true)
            let node = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("node")
            let entry = resources.appendingPathComponent("dist/main.js")
            guard manager.isExecutableFile(atPath: node.path), manager.fileExists(atPath: entry.path) else {
                throw RuntimeFailure(code: "runtime.missing", message: "The bundled agent runtime is missing. Reinstall Trigrams.")
            }
            let cwd = workingDirectory(dataDirectory)
            try manager.createDirectory(at: cwd, withIntermediateDirectories: true)
            let child = Process()
            child.executableURL = node
            child.currentDirectoryURL = resources
            #if APP_STORE
            let profile = "store"
            #else
            let profile = "community"
            #endif
            child.arguments = [entry.path, "--socket", socket, "--token", token, "--agent-dir", dataDirectory.appendingPathComponent("pi-agent").path, "--cwd", cwd.path, "--profile", profile]
            var environment = ProcessInfo.processInfo.environment
            environment["TMPDIR"] = runtime.path
            environment["TMP"] = runtime.path
            environment["TEMP"] = runtime.path
            child.environment = environment
            let logs = dataDirectory.appendingPathComponent("logs", isDirectory: true)
            try manager.createDirectory(at: logs, withIntermediateDirectories: true)
            let logURL = logs.appendingPathComponent("agent.log")
            // Rotate before launch so plugin output cannot grow without bound.
            if let size = try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 2 * 1024 * 1024 {
                let previous = logs.appendingPathComponent("agent.previous.log")
                if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
                try manager.moveItem(at: logURL, to: previous)
            }
            if !manager.fileExists(atPath: logURL.path) { manager.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            logHandle = handle
            child.standardOutput = handle
            child.standardError = handle
            child.terminationHandler = { [weak self] child in
                let code = child.terminationStatus
                Task { @MainActor in
                    guard let self, self.process === child else { return }
                    let message = "The agent stopped (exit \(code)). See the local agent log for details."
                    self.fail(RuntimeFailure(code: "runtime.exited", message: message))
                    self.stop()
                    self.onNotification?("runtime.disconnected", .object(["message": .string(message)]))
                }
            }
            process = child
            try child.run()
            let timeout = ContinuousClock.now + .seconds(15)
            while !manager.fileExists(atPath: socket) {
                guard child.isRunning else { throw RuntimeFailure(code: "runtime.start", message: "The agent could not start. See the local agent log.") }
                guard ContinuousClock.now < timeout else { throw RuntimeFailure(code: "runtime.timeout", message: "The agent did not start within 15 seconds.") }
                try await Task.sleep(for: .milliseconds(100))
            }
            try await connect(socket)
            _ = try await request("hello", params: ["version": .number(1), "token": .string(token), "capabilities": .array([.string("terminal-v1")])])
            #if DEBUG
            if arguments.contains("--ui-testing"), let skills = argument("--skill-directory") {
                _ = try await request("settings.update", params: ["skillDirectories": .array([.string(skills)])])
            }
            #endif
            onNotification?("runtime.availability", inference.availability)
        } catch {
            stop()
            throw error
        }
    }

    func request(_ method: String, params: [String: JSONValue] = [:]) async throws -> JSONValue {
        guard let connection else { throw RuntimeFailure(code: "transport.closed", message: "The agent is disconnected.") }
        let id = UUID().uuidString
        var data = try JSONEncoder().encode(JSONValue.object(["id": .string(id), "method": .string(method), "params": .object(params)]))
        guard data.count <= frameLimit else { throw RuntimeFailure(code: "transport.frame", message: "The request exceeds the transport limit.") }
        data.append(10)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                deadlines[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    self?.finish(id, result: .failure(RuntimeFailure(code: "transport.timeout", message: "The agent did not respond to \(method).")))
                }
                connection.send(content: data, completion: .contentProcessed { [weak self] error in
                    guard let error else { return }
                    let message = error.localizedDescription
                    Task { @MainActor in self?.finish(id, result: .failure(RuntimeFailure(code: "transport.send", message: message))) }
                })
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, result: .failure(CancellationError())) }
        }
    }

    func stop() {
        let child = process
        process = nil
        child?.terminationHandler = nil
        if child?.isRunning == true { child?.terminate() }
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        fail(RuntimeFailure(code: "transport.closed", message: "The agent is disconnected."))
        for task in generations.values { task.cancel() }
        generations.removeAll()
        buffer.removeAll()
        try? logHandle?.close()
        logHandle = nil
        if let runtimeDirectory { try? FileManager.default.removeItem(at: runtimeDirectory) }
        runtimeDirectory = nil
    }

    private func connect(_ socket: String) async throws {
        let connection = NWConnection(to: .unix(path: socket), using: .tcp)
        self.connection = connection
        let deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, self.connection === connection, self.connecting != nil else { return }
            self.fail(RuntimeFailure(code: "transport.timeout", message: "The local agent connection timed out."))
            connection.cancel()
        }
        defer { deadline.cancel() }
        try await withCheckedThrowingContinuation { continuation in
            connecting = continuation
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.connection === connection else { return }
                    switch state {
                    case .ready:
                        self.connecting?.resume()
                        self.connecting = nil
                        self.receive(connection)
                    case .failed(let error): self.fail(RuntimeFailure(code: "transport.connect", message: error.localizedDescription))
                    case .waiting(let error): self.fail(RuntimeFailure(code: "transport.connect", message: error.localizedDescription))
                    case .cancelled: self.fail(RuntimeFailure(code: "transport.closed", message: "The agent disconnected."))
                    default: break
                    }
                }
            }
            connection.start(queue: queue)
        }
    }

    private func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            let message = error?.localizedDescription
            Task { @MainActor in
                guard let self, self.connection === connection else { return }
                do {
                    if let data { try self.consume(data) }
                    if complete || message != nil {
                        self.fail(RuntimeFailure(code: "transport.closed", message: message ?? "The agent disconnected."))
                        self.stop()
                        self.onNotification?("runtime.disconnected", .object(["message": .string(message ?? "The agent disconnected.")]))
                    } else { self.receive(connection) }
                } catch {
                    self.fail(error)
                    self.stop()
                    self.onNotification?("runtime.disconnected", .object(["message": .string(error.localizedDescription)]))
                }
            }
        }
    }

    private func consume(_ data: Data) throws {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            guard line.count <= frameLimit else { throw RuntimeFailure(code: "transport.frame", message: "The agent sent an oversized frame.") }
            buffer.removeSubrange(...newline)
            let message = try JSONDecoder().decode(JSONValue.self, from: line)
            if let id = message["id"].string {
                if let error = message["error"].object {
                    finish(id, result: .failure(RuntimeFailure(code: error["code"]?.string ?? "runtime.error", message: error["message"]?.string ?? "Agent error")))
                } else { finish(id, result: .success(message["result"])) }
            } else if let event = message["event"].string {
                let params = message["params"]
                if event == "model.generate" { generate(params) }
                else if event == "model.cancel", let id = params["id"].string { generations.removeValue(forKey: id)?.cancel() }
                else { onNotification?(event, params) }
            }
        }
        guard buffer.count <= frameLimit else { throw RuntimeFailure(code: "transport.frame", message: "The agent sent an oversized frame.") }
    }

    private func generate(_ params: JSONValue) {
        guard let id = params["id"].string, generations[id] == nil else { return }
        generations[id] = Task { [weak self] in
            guard let self else { return }
            defer { generations.removeValue(forKey: id) }
            do {
                let response = try await inference.generate(params) { text in
                    _ = try await self.request("model.delta", params: ["id": .string(id), "text": .string(text)])
                }
                try Task.checkCancellation()
                _ = try await request("model.complete", params: ["id": .string(id), "response": response])
            } catch is CancellationError {
                // Cancellation was initiated by pi; do not submit a late result.
            } catch {
                let code = (error as? InferenceFailure)?.code ?? "model.generation"
                _ = try? await request("model.fail", params: ["id": .string(id), "code": .string(code), "message": .string(error.localizedDescription)])
            }
        }
    }

    private func finish(_ id: String, result: Result<JSONValue, any Error>) {
        deadlines.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func fail(_ error: any Error) {
        connecting?.resume(throwing: error)
        connecting = nil
        for id in Array(pending.keys) { finish(id, result: .failure(error)) }
    }

    private func dataDirectoryURL() throws -> URL {
        #if DEBUG
        if arguments.contains("--ui-testing"), let path = argument("--data-directory") { return URL(fileURLWithPath: path, isDirectory: true) }
        #endif
        return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Trigrams", isDirectory: true)
    }

    private func runtimeBaseDirectory() -> URL {
        #if DEBUG
        if arguments.contains("--ui-testing"), let path = argument("--runtime-directory") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return FileManager.default.temporaryDirectory
    }

    private func workingDirectory(_ data: URL) -> URL {
        #if DEBUG
        if arguments.contains("--ui-testing"), let path = argument("--working-directory") { return URL(fileURLWithPath: path, isDirectory: true) }
        #endif
        return data.appendingPathComponent("Workspace", isDirectory: true)
    }

    private func argument(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
