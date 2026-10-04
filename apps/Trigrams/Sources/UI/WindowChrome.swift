import AppKit
import SwiftUI

struct WindowChrome: View {
    @Binding var window: NSWindow?
    @Environment(\.nanoPalette) private var palette
    var body: some View {
        HStack(spacing: 2) {
            IconButton(icon: .close, label: String(localized: "Close window"), identifier: "windowCloseButton") { window?.performClose(nil) }
            IconButton(icon: .minus, label: String(localized: "Minimize window"), identifier: "windowMinimizeButton") { window?.miniaturize(nil) }
            IconButton(icon: .expand, label: String(localized: "Zoom window"), identifier: "windowZoomButton") { window?.zoom(nil) }
        }
        .foregroundStyle(palette.secondary)
    }
}

struct WindowConfiguration: NSViewRepresentable {
    @Binding var window: NSWindow?
    func makeNSView(context: Context) -> NSView {
        let view = WindowObserverView()
        view.onWindow = { window in
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.toolbar = nil
            window.isMovableByWindowBackground = false
            window.minSize = NSSize(width: 800, height: 560)
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
            Task { @MainActor in self.window = window }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor private final class WindowObserverView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindow?(window) }
    }
}

struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor private final class DragView: NSView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
            if action == "Minimize" { window?.miniaturize(nil) }
            else if action != "None" { window?.zoom(nil) }
        } else { window?.performDrag(with: event) }
    }
}
