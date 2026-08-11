import AppKit
import SwiftUI

struct CanvasView: View {
    @Bindable var doc: Document
    let page: Page

    @State private var grab: Grab?
    @State private var live: Segment?
    @State private var zoomBase: Double?
    @State private var hovered: Overlay.Grip?
    @State private var inside = false
    @State private var scrollWatch: Any?
    @FocusState private var focused: Bool

    private enum Grab {
        case create(CGPoint)
        case move(id: Segment.ID, handle: Handle, anchor: CGPoint)
        case offset(id: Segment.ID, base: Double, from: CGPoint)
    }

    private static let space = "board"

    /// A slim black cross with a white backing, as the ⇧⌘4 screen selector draws it.
    @MainActor private static let crosshair: Image = {
        let side: CGFloat = 25
        let mid = side / 2
        let gap: CGFloat = 3
        let arms = NSBezierPath()
        arms.move(to: CGPoint(x: 0, y: mid))
        arms.line(to: CGPoint(x: mid - gap, y: mid))
        arms.move(to: CGPoint(x: mid + gap, y: mid))
        arms.line(to: CGPoint(x: side, y: mid))
        arms.move(to: CGPoint(x: mid, y: 0))
        arms.line(to: CGPoint(x: mid, y: mid - gap))
        arms.move(to: CGPoint(x: mid, y: mid + gap))
        arms.line(to: CGPoint(x: mid, y: side))

        let drawn = NSImage(size: CGSize(width: side, height: side))
        drawn.lockFocus()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        arms.lineWidth = 3
        arms.stroke()
        NSColor.black.setStroke()
        arms.lineWidth = 1
        arms.stroke()
        drawn.unlockFocus()
        return Image(nsImage: drawn)
    }()

    private var boardSize: CGSize {
        CGSize(width: page.image.size.width * doc.zoom, height: page.image.size.height * doc.zoom)
    }

    /// The live segment replaces its stored twin, or appends while a new line is being drawn.
    private var shown: [Segment] {
        var all = page.segments
        guard let live else { return all }
        if let index = all.firstIndex(where: { $0.id == live.id }) {
            all[index] = live
        } else {
            all.append(live)
        }
        return all
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                // The min frame centres a small board; the inner board keeps the
                // exact image rect, so its named space maps 1:1 to image points.
                ZStack { board }
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            .background(.quaternary)
            .onAppear {
                doc.viewport = geo.size
                doc.fitZoom()
                focused = true
                watchScroll()
            }
            .onDisappear {
                if let scrollWatch { NSEvent.removeMonitor(scrollWatch) }
                scrollWatch = nil
            }
            .onChange(of: geo.size) { _, size in doc.viewport = size }
            .overlay(alignment: .bottomLeading) { zoomReadout }
        }
        .simultaneousGesture(magnify)
    }

    private var zoomReadout: some View {
        Text("\(Int((doc.zoom * 100).rounded()))%")
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .padding(10)
            .allowsHitTesting(false)
    }

    private var board: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: page.image)
                .resizable()
                .interpolation(.high)
            Overlay(segments: shown,
                    captions: shown.map { doc.caption(for: $0) },
                    referenceID: page.referenceID,
                    selectedID: doc.selectedSegmentID,
                    activeHandle: doc.selectedHandle,
                    hovered: hovered,
                    tint: doc.lineColor,
                    scale: doc.zoom)
        }
        .frame(width: boardSize.width, height: boardSize.height)
        .coordinateSpace(.named(Self.space))
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
            guard case .active(let location) = phase else {
                hovered = nil
                inside = false
                return
            }
            inside = true
            hovered = grip(near: imagePoint(location))
        }
        .pointerStyle(hovered == nil ? .image(Self.crosshair, hotSpot: .center) : .grabIdle)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .gesture(drag)
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], action: arrow)
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            doc.removeSelected()
            return .handled
        }
    }

    private func arrow(_ press: KeyPress) -> KeyPress.Result {
        guard doc.selectedSegmentID != nil else { return .ignored }
        let step: Double = press.modifiers.contains(.shift) ? 10 : 1
        switch press.key {
        case .upArrow: doc.nudge(dx: 0, dy: -step)
        case .downArrow: doc.nudge(dx: 0, dy: step)
        case .leftArrow: doc.nudge(dx: -step, dy: 0)
        default: doc.nudge(dx: step, dy: 0)
        }
        return .handled
    }

    /// Both conventions: ⌘ scroll as in browsers and Figma, ⌥ scroll as in Photoshop.
    private func watchScroll() {
        guard scrollWatch == nil else { return }
        scrollWatch = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let held = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard inside, held.contains(.command) || held.contains(.option) else { return event }
            let travel = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY / 120
                : event.scrollingDeltaY / 12
            doc.stepZoom(exp(travel))
            return nil
        }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = zoomBase ?? doc.zoom
                zoomBase = base
                doc.zoom = min(max(base * value.magnification, 0.05), 40)
            }
            .onEnded { _ in zoomBase = nil }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let started = grab ?? begin(at: imagePoint(value.startLocation))
                grab = started
                live = segment(for: started, at: imagePoint(value.location))
            }
            .onEnded { value in
                focused = true
                let travel = hypot(value.translation.width, value.translation.height)
                if travel < 3 {
                    select(at: imagePoint(value.startLocation))
                } else if let grab, let final = segment(for: grab, at: imagePoint(value.location)) {
                    commit(final, for: grab)
                }
                grab = nil
                live = nil
            }
    }

    private func imagePoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / doc.zoom, y: p.y / doc.zoom)
    }

    private var tolerance: Double { 12 / doc.zoom }

    /// Only the selected line offers handles — the one already showing the rings.
    private func grip(near point: CGPoint) -> Overlay.Grip? {
        let selected = page.segments.filter { $0.id == doc.selectedSegmentID }
        guard let hit = handleHit(in: selected, near: point, tolerance: tolerance) else {
            return nil
        }
        return Overlay.Grip(id: hit.id, handle: hit.handle)
    }

    /// Handles move what was measured; the dimension line's body slides it off the feature.
    private func begin(at point: CGPoint) -> Grab {
        if let hit = grip(near: point),
           let held = page.segments.first(where: { $0.id == hit.id }) {
            doc.selectedHandle = hit.handle
            return .move(id: hit.id, handle: hit.handle,
                         anchor: hit.handle == .start ? held.end : held.start)
        }
        if let held = doc.selectedSegment,
           distance(from: point, to: displaced(held)) <= tolerance {
            return .offset(id: held.id, base: held.offset, from: point)
        }
        return .create(point)
    }

    private func segment(for grab: Grab, at point: CGPoint) -> Segment? {
        let locked = NSEvent.modifierFlags.contains(.shift)
        switch grab {
        case .create(let origin):
            return Segment(start: origin, end: axisLocked(origin, point, locked: locked))
        case .move(let id, let handle, let anchor):
            guard var held = page.segments.first(where: { $0.id == id }) else { return nil }
            let moved = axisLocked(anchor, point, locked: locked)
            if handle == .start { held.start = moved } else { held.end = moved }
            return held
        case .offset(let id, let base, let from):
            guard var held = page.segments.first(where: { $0.id == id }) else { return nil }
            let across = normal(of: held)
            held.offset = base + (point.x - from.x) * across.x + (point.y - from.y) * across.y
            return held
        }
    }

    private func commit(_ segment: Segment, for grab: Grab) {
        switch grab {
        case .create:
            doc.add(segment)
            doc.selectedHandle = .end
        case .move, .offset:
            doc.replace(segment)
        }
    }

    /// Clicking a handle chooses that end; clicking the line chooses the whole line.
    /// Hit-test where the line is drawn, not where it was measured.
    private func select(at point: CGPoint) {
        if let hit = grip(near: point) {
            doc.selectedHandle = hit.handle
            return
        }
        doc.selectedSegmentID = segmentHit(in: page.segments.map(displaced),
                                           near: point, tolerance: tolerance)
        doc.selectedHandle = nil
    }
}
