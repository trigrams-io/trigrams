import AppKit
import XCTest

/// Black-box tests launch the shipped app, its bundled Node executable and pi.
/// The DEBUG model fixture provides a repeatable inference response only.
@MainActor
final class TrigramsUITests: XCTestCase {
    private let response = "Trigrams completed the request."

    func testSidecarRestartPreservesTheSelectedChatAndIgnoresOldConnections() throws {
        let fixture = try makeFixture()
        let app = launch(fixture)
        defer { app.terminate(); try? FileManager.default.removeItem(at: fixture) }
        replace(app.textViews["composerInput"], with: "Keep this chat after a sidecar restart", in: app)
        click(app.buttons["sendButton"])
        XCTAssertTrue(app.staticTexts[response].firstMatch.waitForExistence(timeout: 25))
        waitEnabled(app.buttons["newChatButton"])
        for _ in 0..<2 {
            let running = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "io.trigrams.app").first)
            let childLookup = Process()
            let output = Pipe()
            childLookup.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            childLookup.arguments = ["-P", String(running.processIdentifier)]
            childLookup.standardOutput = output
            try childLookup.run()
            childLookup.waitUntilExit()
            let children = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.split(separator: "\n").compactMap { Int32($0) } ?? []
            XCTAssertFalse(children.isEmpty)
            for child in children { XCTAssertEqual(kill(child, SIGTERM), 0) }
            XCTAssertTrue(app.buttons["retryRuntimeButton"].waitForExistence(timeout: 10))
            click(app.buttons["retryRuntimeButton"])
            waitEnabled(app.buttons["newChatButton"])
            XCTAssertEqual(app.staticTexts["chatTitle"].label, "Keep this chat after a sidecar restart")
            XCTAssertTrue(app.staticTexts[response].firstMatch.exists)
        }
        replace(app.textViews["composerInput"], with: "Continue after restarting", in: app)
        click(app.buttons["sendButton"])
        XCTAssertTrue(app.staticTexts["Continue after restarting"].firstMatch.waitForExistence(timeout: 10))
        waitEnabled(app.buttons["newChatButton"])
        XCTAssertFalse(app.buttons["retryRuntimeButton"].exists)
    }

    func testSearchIsCompactAndComposerAdaptsToSidebarAndWindowSize() throws {
        let fixture = try makeFixture()
        let app = launch(fixture)
        defer { app.terminate(); try? FileManager.default.removeItem(at: fixture) }
        XCTAssertFalse(app.textFields["chatSearchField"].exists)
        XCTAssertFalse(app.buttons["composerSkillsButton"].exists)
        let toggle = app.buttons["sidebarToggleButton"]
        let controls = app.windows.firstMatch.buttons.allElementsBoundByIndex.filter { $0.frame.width > 0 && $0.frame.maxX < toggle.frame.minX && $0.frame.minY < toggle.frame.maxY }
        XCTAssertEqual(controls.count, 3, "The window keeps its three standard AppKit controls.")
        for control in controls { XCTAssertEqual(control.frame.midY, toggle.frame.midY, accuracy: 1) }
        click(app.buttons["chatSearchButton"])
        XCTAssertTrue(app.textFields["chatSearchField"].waitForExistence(timeout: 5))
        click(app.buttons["chatSearchButton"])
        XCTAssertFalse(app.textFields["chatSearchField"].exists)
        let editor = app.textViews["composerInput"]
        let initial = editor.frame.width
        click(app.buttons["sidebarToggleButton"])
        XCTAssertGreaterThan(editor.frame.width, initial + 180)
        click(app.buttons["sidebarToggleButton"])
        let window = app.windows.firstMatch
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        corner.press(forDuration: 0.1, thenDragTo: corner.withOffset(CGVector(dx: 140, dy: 50)))
        XCTAssertGreaterThan(editor.frame.width, initial + 80)
        click(app.buttons["settingsButton"])
        for theme in ["light", "dark", "system"] { XCTAssertTrue(app.buttons["theme.\(theme)"].isHittable) }
        let panel = app.descendants(matching: .any)["settingsPanel"]
        XCTAssertLessThan(panel.frame.width, window.frame.width)
        XCTAssertLessThan(panel.frame.height, window.frame.height)
        click(app.buttons["closeSettingsButton"])
    }

    func testChatPersistsAndReopensAfterRelaunch() throws {
        let fixture = try makeFixture()
        let app = launch(fixture)
        defer { app.terminate(); try? FileManager.default.removeItem(at: fixture) }

        click(app.buttons["newChatButton"])
        replace(app.textViews["composerInput"], with: "Remember this end-to-end conversation", in: app)
        click(app.buttons["sendButton"])
        XCTAssertTrue(app.staticTexts[response].firstMatch.waitForExistence(timeout: 25), app.debugDescription)
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "chatRow."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        let firstSession = rows.firstMatch.identifier

        // Create another session, then return through the searchable sidebar.
        waitEnabled(app.buttons["newChatButton"])
        click(app.buttons["newChatButton"])
        replace(app.textViews["composerInput"], with: "A second conversation", in: app)
        click(app.buttons["sendButton"])
        XCTAssertTrue(app.staticTexts[response].firstMatch.waitForExistence(timeout: 25))
        waitEnabled(app.buttons["newChatButton"])
        XCTAssertFalse(app.textFields["chatSearchField"].exists)
        click(app.buttons["chatSearchButton"])
        let search = app.textFields["chatSearchField"]
        replace(search, with: "Remember this", in: app)
        click(app.descendants(matching: .any)[firstSession])
        XCTAssertTrue(app.staticTexts["Remember this end-to-end conversation"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["chatTitle"].label, "Remember this end-to-end conversation")
        XCTAssertEqual(app.descendants(matching: .any)[firstSession].label, "Remember this end-to-end conversation")
        replace(app.textViews["composerInput"], with: "An unsent draft", in: app)
        click(app.descendants(matching: .any)[firstSession])
        XCTAssertEqual(app.textViews["composerInput"].value as? String, "An unsent draft")
        replace(search, with: "", in: app)

        app.terminate()
        app.launch()
        waitEnabled(app.buttons["newChatButton"])
        click(app.descendants(matching: .any)[firstSession])
        XCTAssertTrue(app.staticTexts[response].firstMatch.waitForExistence(timeout: 10), "The assistant response must be read from the persisted pi session.")
        XCTAssertTrue(app.staticTexts["Remember this end-to-end conversation"].firstMatch.exists)
        XCTAssertEqual(app.staticTexts["chatTitle"].label, "Remember this end-to-end conversation")

        // The visible result must also exist in pi's actual JSONL store.
        let enumerator = FileManager.default.enumerator(at: fixture.appending(path: "data"), includingPropertiesForKeys: nil)
        let sessions = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "jsonl" }
        XCTAssertFalse(sessions.isEmpty, "pi must persist the conversation to a session JSONL file.")
        XCTAssertTrue(try sessions.contains { try String(contentsOf: $0, encoding: .utf8).contains(response) })
    }

    func testStopThenQueueAndSteerThroughRealRuntime() throws {
        let fixture = try makeFixture()
        let app = launch(fixture)
        defer { app.terminate(); try? FileManager.default.removeItem(at: fixture) }

        click(app.buttons["newChatButton"])
        replace(app.textViews["composerInput"], with: "[slow] Start a cancellable request", in: app)
        click(app.buttons["sendButton"])
        click(app.buttons["stopButton"])
        waitEnabled(app.buttons["newChatButton"])
        XCTAssertTrue(app.staticTexts["Stopped"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)

        replace(app.textViews["composerInput"], with: "[slow] Begin a request for follow-up", in: app)
        click(app.buttons["sendButton"])
        XCTAssertTrue(app.buttons["followUpButton"].waitForExistence(timeout: 5))
        replace(app.textViews["composerInput"], with: "A queued follow-up", in: app)
        click(app.buttons["followUpButton"])
        XCTAssertTrue(app.staticTexts["A queued follow-up"].firstMatch.waitForExistence(timeout: 20))
        waitEnabled(app.buttons["newChatButton"], timeout: 30)
        XCTAssertTrue(app.staticTexts[response].firstMatch.exists)

        replace(app.textViews["composerInput"], with: "[slow] Begin a request for steering", in: app)
        click(app.buttons["sendButton"])
        replace(app.textViews["composerInput"], with: "A steering instruction", in: app)
        click(app.buttons["steerButton"])
        waitEnabled(app.buttons["newChatButton"], timeout: 30)
        XCTAssertTrue(app.staticTexts["A steering instruction"].firstMatch.exists)
    }

    func testAppearanceAndSystemPromptPersistAndReset() throws {
        let fixture = try makeFixture()
        let app = launch(fixture)
        defer { app.terminate(); try? FileManager.default.removeItem(at: fixture) }

        click(app.buttons["settingsButton"])
        for theme in ["light", "dark", "system", "dark"] {
            click(app.buttons["theme.\(theme)"])
            waitValue(app.buttons["theme.\(theme)"], containing: "Selected")
        }
        click(app.buttons["settingsTab.systemPrompt"])
        let editor = app.textViews["systemPromptEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let defaultPrompt = editor.value as? String ?? ""
        XCTAssertFalse(defaultPrompt.isEmpty)
        let customPrompt = "Answer concisely and preserve every user constraint."
        replace(editor, with: customPrompt, in: app)
        click(app.buttons["saveSystemPromptButton"])
        XCTAssertTrue(app.staticTexts["System prompt saved"].waitForExistence(timeout: 10))
        click(app.buttons["closeSettingsButton"])

        app.terminate()
        app.launch()
        waitEnabled(app.buttons["newChatButton"])
        click(app.buttons["settingsButton"])
        waitValue(app.buttons["theme.dark"], containing: "Selected")
        click(app.buttons["settingsTab.systemPrompt"])
        waitValue(app.textViews["systemPromptEditor"], containing: customPrompt)
        click(app.buttons["resetSystemPromptButton"])
        waitValue(app.textViews["systemPromptEditor"], containing: defaultPrompt)
        XCTAssertTrue(app.staticTexts["Default system prompt restored"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        waitEnabled(app.buttons["newChatButton"])
        click(app.buttons["settingsButton"])
        click(app.buttons["settingsTab.systemPrompt"])
        waitValue(app.textViews["systemPromptEditor"], containing: defaultPrompt)
    }

    func testStandardSkillsEnableDisableAndReloadPersist() throws {
        let fixture = try makeFixture()
        try writeSkill("fixture-skill", in: fixture)
        let app = launch(fixture)
        defer { app.terminate(); try? FileManager.default.removeItem(at: fixture) }

        click(app.buttons["settingsButton"])
        click(app.buttons["settingsTab.skills"])
        let toggle = app.buttons["skillToggle.fixture-skill"]
        waitValue(toggle, containing: "Enabled")
        click(toggle)
        waitValue(toggle, containing: "Disabled")

        app.terminate()
        app.launch()
        waitEnabled(app.buttons["newChatButton"])
        click(app.buttons["settingsButton"])
        click(app.buttons["settingsTab.skills"])
        waitValue(app.buttons["skillToggle.fixture-skill"], containing: "Disabled")
        click(app.buttons["skillToggle.fixture-skill"])
        waitValue(app.buttons["skillToggle.fixture-skill"], containing: "Enabled")

        try writeSkill("added-during-run", in: fixture)
        click(app.buttons["reloadResourcesButton"])
        waitValue(app.buttons["skillToggle.added-during-run"], containing: "Enabled")
        XCTAssertTrue(app.staticTexts["Resources reloaded"].waitForExistence(timeout: 10))
    }

    func testUnavailableOnDeviceModelShowsReasonAndDisablesSending() throws {
        let fixture = try makeFixture()
        let app = launch(fixture, extra: ["--ui-testing-unavailable"])
        defer { app.terminate(); try? FileManager.default.removeItem(at: fixture) }

        click(app.buttons["newChatButton"])
        replace(app.textViews["composerInput"], with: "This must not dispatch inference", in: app)
        XCTAssertFalse(app.buttons["sendButton"].isEnabled)
        click(app.buttons["modelStatus"])
        XCTAssertTrue(app.staticTexts["The on-device model is unavailable in this test."].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
    }

    func testReadToolShowsActualFileAndCompleteResult() throws {
        let fixture = try makeFixture()
        let contents = "The read tool executed in the real workspace."
        try contents.write(to: fixture.appending(path: "workspace/fixture.txt"), atomically: true, encoding: .utf8)
        let app = launch(fixture)
        defer { app.terminate(); try? FileManager.default.removeItem(at: fixture) }

        click(app.buttons["newChatButton"])
        replace(app.textViews["composerInput"], with: "[read:fixture.txt] Read the workspace fixture", in: app)
        click(app.buttons["sendButton"])
        XCTAssertTrue(app.staticTexts["Read file: \(contents)"].firstMatch.waitForExistence(timeout: 25), app.debugDescription)
        let tool = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "toolRecord.")).firstMatch
        click(tool)
        waitValue(tool, containing: "Expanded")
        XCTAssertTrue(app.staticTexts[contents].firstMatch.exists)
        let toolID = String(tool.identifier.dropFirst("toolRecord.".count))
        click(app.buttons["completeToolResult.\(toolID)"])
        XCTAssertTrue(app.staticTexts["rawToolResult.\(toolID)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["rawToolResult.\(toolID)"].label.contains(contents))
        click(app.buttons["completeToolResult.\(toolID)"])
        click(tool)
        waitValue(tool, containing: "Collapsed")
    }

    func testLargeToolResultShowsPagedPreviewAndCompleteOriginal() throws {
        let fixture = try makeFixture()
        let contents = String(repeating: "工具结果需要完整保存。\n", count: 400) + "ORIGINAL_FINAL_LINE"
        try contents.write(to: fixture.appending(path: "workspace/large.txt"), atomically: true, encoding: .utf8)
        let app = launch(fixture)
        defer { app.terminate(); try? FileManager.default.removeItem(at: fixture) }
        replace(app.textViews["composerInput"], with: "[read:large.txt] Read the large fixture", in: app)
        click(app.buttons["sendButton"])
        let reply = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Read file: Paged tool output")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 25), app.debugDescription)
        let tool = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "toolRecord.")).firstMatch
        click(tool)
        let id = String(tool.identifier.dropFirst("toolRecord.".count))
        click(app.buttons["completeToolResult.\(id)"])
        let raw = app.staticTexts["rawToolResult.\(id)"]
        XCTAssertTrue(raw.waitForExistence(timeout: 10))
        XCTAssertTrue(raw.label.contains("ORIGINAL_FINAL_LINE"))
    }

    func testBranchForkAndSidebarVisibility() throws {
        let fixture = try makeFixture()
        let app = launch(fixture)
        defer { app.terminate(); try? FileManager.default.removeItem(at: fixture) }

        click(app.buttons["newChatButton"])
        let original = "Fork this first user turn"
        replace(app.textViews["composerInput"], with: original, in: app)
        click(app.buttons["sendButton"])
        XCTAssertTrue(app.staticTexts[response].firstMatch.waitForExistence(timeout: 25))
        waitEnabled(app.buttons["newChatButton"])
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "chatRow."))
        let originalSession = rows.firstMatch.identifier
        click(app.buttons["sidebarToggleButton"])
        XCTAssertFalse(app.buttons["chatSearchButton"].exists)
        click(app.buttons["sidebarToggleButton"])
        XCTAssertTrue(app.buttons["chatSearchButton"].waitForExistence(timeout: 5))

        click(app.buttons["branchButton"])
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "branchEntry.", original)).firstMatch
        click(entry)
        click(app.buttons["forkBranchButton"])
        XCTAssertTrue(app.textViews["composerInput"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)[originalSession].exists, "Forking must preserve the source session.")
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count >= 2"), object: rows)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
        click(app.buttons["branchButton"])
        click(app.buttons["closeBranchesButton"])
    }

    func testExtensionNativeDialogsStatusWidgetAndPersistedAnswers() throws {
        let fixture = try makeFixture()
        try writeNativeExtension(in: fixture)
        let app = launch(fixture)
        defer { app.terminate(); try? FileManager.default.removeItem(at: fixture) }

        click(app.buttons["newChatButton"])
        replace(app.textViews["composerInput"], with: "/native-dialogs", in: app)
        click(app.buttons["sendButton"])
        XCTAssertTrue(app.staticTexts["Native confirmation"].waitForExistence(timeout: 10))
        click(app.buttons["dialogAcceptButton"])
        XCTAssertTrue(app.staticTexts["Native selection"].waitForExistence(timeout: 10))
        click(app.buttons["dialogOption.two"])
        XCTAssertTrue(app.staticTexts["Native input"].waitForExistence(timeout: 10))
        replace(app.textViews["dialogInput"], with: "typed input", in: app)
        click(app.buttons["dialogSubmitButton"])
        XCTAssertTrue(app.staticTexts["Native editor"].waitForExistence(timeout: 10))
        replace(app.textViews["dialogInput"], with: "edited body", in: app)
        click(app.buttons["dialogSubmitButton"])
        let completion = "Native dialogs complete: true | two | typed input | edited body"
        XCTAssertTrue(app.staticTexts[completion].firstMatch.waitForExistence(timeout: 10), app.debugDescription)

        let enumerator = FileManager.default.enumerator(at: fixture.appending(path: "data"), includingPropertiesForKeys: nil)
        let sessions = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "jsonl" }
        XCTAssertTrue(try sessions.contains { try String(contentsOf: $0, encoding: .utf8).contains("native-dialog-results") })
        replace(app.textViews["composerInput"], with: "/native-cancel", in: app)
        click(app.buttons["sendButton"])
        XCTAssertTrue(app.staticTexts["Cancel this confirmation"].waitForExistence(timeout: 10))
        click(app.buttons["dialogCancelButton"])
        XCTAssertTrue(app.staticTexts["Native confirmation cancelled"].firstMatch.waitForExistence(timeout: 10))
    }

    func testExtensionTUIReceivesActualKeyboardInput() throws {
        let fixture = try makeFixture()
        try writeNativeExtension(in: fixture)
        let app = launch(fixture)
        defer { app.terminate(); try? FileManager.default.removeItem(at: fixture) }

        click(app.buttons["newChatButton"])
        replace(app.textViews["composerInput"], with: "/native-tui", in: app)
        click(app.buttons["sendButton"])
        let terminal = app.descendants(matching: .any)["compatibilityTerminal"]
        XCTAssertTrue(terminal.waitForExistence(timeout: 10), app.debugDescription)
        terminal.click()
        app.typeKey("y", modifierFlags: [])
        click(app.buttons["closeCompatibilityButton"])
        XCTAssertTrue(app.staticTexts["Native TUI accepted keyboard input"].firstMatch.waitForExistence(timeout: 10))
        replace(app.textViews["composerInput"], with: "The main composer still works", in: app)
        click(app.buttons["sendButton"])
        XCTAssertTrue(app.staticTexts[response].firstMatch.waitForExistence(timeout: 25))
    }

    func testMarkdownCodeAndTableRenderAndCodeCopiesToPasteboard() throws {
        let fixture = try makeFixture()
        let app = launch(fixture)
        defer { app.terminate(); try? FileManager.default.removeItem(at: fixture) }

        click(app.buttons["newChatButton"])
        replace(app.textViews["composerInput"], with: "[markdown] Show a formatted answer", in: app)
        click(app.buttons["sendButton"])
        XCTAssertTrue(app.staticTexts["Details"].firstMatch.waitForExistence(timeout: 25))
        XCTAssertTrue(app.staticTexts["Action"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Completed"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["let answer = 42"].firstMatch.exists)
        click(app.buttons["Copy code"].firstMatch)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "let answer = 42")
    }

    private func makeFixture() throws -> URL {
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = ProcessInfo.processInfo.environment["TRIGRAMS_TEST_ROOT"] ?? sourceRoot.appending(path: "build/UIFixtures").path
        let fixture = URL(fileURLWithPath: path).appending(path: UUID().uuidString, directoryHint: .isDirectory)
        for name in ["data", "workspace", "skills"] {
            try FileManager.default.createDirectory(at: fixture.appending(path: name), withIntermediateDirectories: true)
        }
        return fixture
    }

    private func writeSkill(_ name: String, in fixture: URL) throws {
        let directory = fixture.appending(path: "skills/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        ---
        name: \(name)
        description: A real local skill loaded by the end-to-end test.
        ---
        Use this skill when the user requests a deterministic test scenario.
        """.write(to: directory.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
    }

    private func writeNativeExtension(in fixture: URL) throws {
        let directory = fixture.appending(path: "data/pi-agent/extensions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        import { Text } from '@earendil-works/pi-tui';
        export default function(pi) {
          pi.registerCommand('native-dialogs', { handler: async (_args, ctx) => {
            ctx.ui.setStatus('native-fixture', 'Native extension ready');
            ctx.ui.setWidget('native-fixture', ['Native widget content']);
            ctx.ui.setEditorText('Extension editor seed');
            const yes = await ctx.ui.confirm('Native confirmation', 'Continue with the real extension?');
            const pick = await ctx.ui.select('Native selection', ['one', 'two']);
            const input = await ctx.ui.input('Native input', 'Enter test input');
            const edited = await ctx.ui.editor('Native editor', 'Initial extension body');
            pi.appendEntry('native-dialog-results', { yes, pick, input, edited });
            ctx.ui.notify(`Native dialogs complete: ${yes} | ${pick} | ${input} | ${edited}`);
            ctx.ui.setStatus('native-fixture', undefined);
            ctx.ui.setWidget('native-fixture', undefined);
            ctx.ui.setEditorText('');
          }});
          pi.registerCommand('native-cancel', { handler: async (_args, ctx) => {
            const yes = await ctx.ui.confirm('Cancel this confirmation', 'Decline this request.');
            if (!yes) ctx.ui.notify('Native confirmation cancelled');
          }});
          pi.registerCommand('native-tui', { handler: async (_args, ctx) => {
            ctx.ui.setHeader((_tui, theme) => new Text(theme.bold('Native terminal fixture'), 0, 0));
            const accepted = await ctx.ui.custom((_tui, theme, _keys, done) => ({
              render: width => [theme.fg('accent', `Press y to accept in ${width} columns`)],
              handleInput: data => { if (data === 'y') done(true); },
              invalidate() {}
            }), { overlay: true, overlayOptions: { width: '70%', anchor: 'center' } });
            pi.appendEntry('native-tui-result', { accepted });
            if (accepted) ctx.ui.notify('Native TUI accepted keyboard input');
            ctx.ui.setHeader(undefined);
          }});
        }
        """.write(to: directory.appending(path: "native-fixture.ts"), atomically: true, encoding: .utf8)
    }

    private func launch(_ fixture: URL, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-NSTreatUnknownArgumentsAsOpen", "NO", "--ui-testing", "--data-directory", fixture.appending(path: "data").path,
                               "--working-directory", fixture.appending(path: "workspace").path,
                               "--skill-directory", fixture.appending(path: "skills").path,
                               "--runtime-directory", ProcessInfo.processInfo.environment["TRIGRAMS_TEST_TEMP"] ?? "/Volumes/SSD/Developer/Codex/tmp"] + extra
        for name in ["TMPDIR", "TMP", "TEMP"] {
            if let value = ProcessInfo.processInfo.environment[name] { app.launchEnvironment[name] = value }
        }
        app.launch()
        app.activate()
        waitEnabled(app.buttons["newChatButton"], timeout: 25)
        return app
    }

    private func click(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing element: \(element)")
        waitEnabled(element)
        element.click()
    }

    private func replace(_ element: XCUIElement, with text: String, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        element.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        if !text.isEmpty {
            // Paste through the real editor so tests are independent of the
            // Mac's active input method and keyboard layout.
            let pasteboard = NSPasteboard.general
            let previous: [NSPasteboardItem] = pasteboard.pasteboardItems?.map { item in
                let copy = NSPasteboardItem()
                for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
                return copy
            } ?? []
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            app.typeKey("v", modifierFlags: .command)
            pasteboard.clearContents()
            if !previous.isEmpty { pasteboard.writeObjects(previous) }
        }
    }

    private func waitEnabled(_ element: XCUIElement, timeout: TimeInterval = 15) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, "Element did not become enabled: \(element)")
    }

    private func waitValue(_ element: XCUIElement, containing value: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, "Expected accessible value '\(value)' for \(element)")
    }
}
