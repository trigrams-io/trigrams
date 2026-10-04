import AppKit
import SwiftUI

@main
struct TrigramsApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @State private var model: AppModel

    init() {
        TrigramsFont.register()
        let runtime = RuntimeClient()
        _model = State(initialValue: AppModel(runtime: runtime))
        ApplicationDelegate.runtime = runtime
    }

    var body: some Scene {
        WindowGroup { RootView(model: model) }
            .defaultSize(width: 1120, height: 760)
            .windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandGroup(replacing: .toolbar) {}
            }
    }
}

@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    static weak var runtime: (any AppRuntimeServing)?
    func applicationWillTerminate(_ notification: Notification) { Self.runtime?.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
