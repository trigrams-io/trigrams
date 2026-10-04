import AppKit
import SwiftUI

struct WindowConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WindowObserverView()
        view.onWindow = { [weak view] window in
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.toolbar = nil
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: 800, height: 560)
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = false
            }
            view?.centerTrafficLights()
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor private final class WindowObserverView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    private var resizeObserver: NSObjectProtocol?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        if let window {
            onWindow?(window)
            resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.centerTrafficLights() }
            }
        }
    }
    override func layout() {
        super.layout()
        centerTrafficLights()
    }
    func centerTrafficLights() {
        guard let window, let content = window.contentView else { return }
        let top = content.convert(content.bounds, to: nil).maxY
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type), let parent = button.superview else { continue }
            var frame = button.convert(button.bounds, to: nil)
            frame.origin.y = top - 23 - frame.height / 2
            button.setFrameOrigin(parent.convert(frame, from: nil).origin)
        }
    }
}
