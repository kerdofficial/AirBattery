import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    private final class WindowView: NSView {
        var configure: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { configure?(window) }
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = WindowView()
        view.configure = configure
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
