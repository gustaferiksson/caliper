import AppKit
import SwiftUI

/// SwiftUI's pointerStyle is inherited, so it leaks past the view that sets it.
/// A tracking area is bound to one rect and cannot.
struct CursorArea: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> Tracker { Tracker() }

    func updateNSView(_ view: Tracker, context: Context) {
        view.cursor = cursor
    }

    final class Tracker: NSView {
        var cursor: NSCursor = .arrow {
            didSet {
                guard cursor != oldValue, inside else { return }
                cursor.set()
            }
        }
        private var inside = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.cursorUpdate, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self))
        }

        override func cursorUpdate(with event: NSEvent) { cursor.set() }

        override func mouseEntered(with event: NSEvent) {
            inside = true
            cursor.set()
        }

        override func mouseExited(with event: NSEvent) {
            inside = false
            NSCursor.arrow.set()
        }

        /// Never take a click — the SwiftUI gestures underneath need every one.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
