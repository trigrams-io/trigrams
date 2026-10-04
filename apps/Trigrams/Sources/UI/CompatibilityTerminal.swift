import AppKit
import SwiftUI
@preconcurrency import SwiftTerm

/// An emulator for the existing pi session's TUI. It never starts a shell,
/// second pi process, or replacement agent.
struct CompatibilityTerminal: NSViewRepresentable {
    let frames: [TerminalFrame]
    let generation: Int
    let onInput: (String) -> Void
    let onResize: (Int, Int) -> Void
    @Environment(\.nanoPalette) private var palette

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero, font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        view.terminalDelegate = context.coordinator
        view.nativeBackgroundColor = NSColor(palette.background)
        view.nativeForegroundColor = NSColor(palette.foreground)
        view.caretColor = NSColor(palette.salient)
        view.setAccessibilityIdentifier("compatibilityTerminal")
        view.setAccessibilityLabel(String(localized: "Extension terminal"))
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            view.window?.makeFirstResponder(view)
            context.coordinator.reportSize(view)
        }
        return view
    }
    func updateNSView(_ view: TerminalView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.generation != generation {
            coordinator.generation = generation
            coordinator.lastSequence = -1
            view.feed(text: "\u{1B}c")
        }
        for frame in frames where frame.id > coordinator.lastSequence {
            view.feed(text: frame.data)
            coordinator.lastSequence = frame.id
        }
    }

    @MainActor final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        var parent: CompatibilityTerminal
        var lastSequence = -1
        var generation = -1
        private var lastSize = ""
        init(_ parent: CompatibilityTerminal) { self.parent = parent }
        func send(source: TerminalView, data: ArraySlice<UInt8>) { parent.onInput(String(decoding: data, as: UTF8.self)) }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { resize(columns: newCols, rows: newRows) }
        func reportSize(_ source: TerminalView) { resize(columns: source.getTerminal().cols, rows: source.getTerminal().rows) }
        private func resize(columns: Int, rows: Int) {
            let size = "\(columns)x\(rows)"
            guard size != lastSize, columns > 0, rows > 0 else { return }
            lastSize = size
            parent.onResize(columns, rows)
        }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        func clipboardCopy(source: TerminalView, content: Data) {
            guard let text = String(data: content, encoding: .utf8) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
