import AppKit
import SwiftUI

/// Real AppKit text input retains IME composition, selection, paste, and undo.
/// Its enclosing surface and scroll decoration are drawn by Trigrams.
struct NativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var identifier: String
    var placeholder = ""
    var fontSize: CGFloat = 14
    var isComposer = false
    var onSubmit: (() -> Void)?
    var onFocus: ((Bool) -> Void)?
    @Environment(\.nanoPalette) private var palette

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        let view = InputTextView(frame: scroll.contentView.bounds)
        view.isRichText = false
        view.importsGraphics = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isContinuousSpellCheckingEnabled = true
        view.isGrammarCheckingEnabled = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.heightTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 3, height: 5)
        view.delegate = context.coordinator
        view.setAccessibilityIdentifier(identifier)
        view.setAccessibilityLabel(placeholder.isEmpty ? identifier : placeholder)
        scroll.documentView = view
        update(view, coordinator: context.coordinator)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? InputTextView else { return }
        update(view, coordinator: context.coordinator)
    }

    private func update(_ view: InputTextView, coordinator: Coordinator) {
        if view.string != text, !view.hasMarkedText() {
            let selected = view.selectedRanges
            view.string = text
            view.selectedRanges = selected.map { range in
                let value = range.rangeValue
                return NSValue(range: NSRange(location: min(value.location, (text as NSString).length), length: 0))
            }
        }
        view.font = NSFont(name: "InterVariable", size: fontSize) ?? .systemFont(ofSize: fontSize)
        view.textColor = NSColor(palette.foreground)
        view.insertionPointColor = NSColor(palette.salient)
        view.selectedTextAttributes = [.backgroundColor: NSColor(palette.salient.opacity(palette.isDark ? 0.38 : 0.18)), .foregroundColor: NSColor(palette.foreground)]
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [.font: view.font!, .foregroundColor: view.textColor!, .paragraphStyle: paragraph]
        view.placeholder = placeholder
        view.placeholderColor = NSColor(palette.secondary)
        view.submitsOnReturn = isComposer
        view.submit = onSubmit
        view.focusChanged = onFocus
        view.needsDisplay = true
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeTextEditor
        init(_ parent: NativeTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

@MainActor private final class InputTextView: NSTextView {
    var submitsOnReturn = false
    var submit: (() -> Void)?
    var focusChanged: ((Bool) -> Void)?
    var placeholder = ""
    var placeholderColor = NSColor.secondaryLabelColor

    override func keyDown(with event: NSEvent) {
        if submitsOnReturn, event.keyCode == 36 || event.keyCode == 76,
           !event.modifierFlags.contains(.shift), !hasMarkedText() {
            submit?()
            return
        }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { focusChanged?(true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { focusChanged?(false) }
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        placeholder.draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height), withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: placeholderColor])
    }
}
