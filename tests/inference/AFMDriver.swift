import Foundation

/// Headless E2E peer using the same production inference service as the app.
@main struct AFMDriver {
    @MainActor static func main() async {
        do {
            let request = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            let result = try await FoundationModelService(arguments: []).generate(request) { _ in }
            FileHandle.standardOutput.write(try JSONEncoder().encode(result))
        } catch {
            FileHandle.standardError.write(Data(error.localizedDescription.utf8))
            exit(1)
        }
    }
}
