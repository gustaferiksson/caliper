import AppKit
import SwiftUI

struct CanvasView: View {
    @Bindable var doc: Document
    let page: Page

    @State private var grab: Grab?
    @State private var live: Segment?
    @State private var zoomBase: Double?
    @FocusState private var focused: Bool

    private enum Grab {
        case create(CGPoint)
        case move(id: Segment.ID, handle: Handle, anchor: CGPoint)
    }

    private static let space = "board"

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
            }
            .onChange(of: geo.size) { _, size in doc.viewport = size }
        }
        .simultaneousGesture(magnify)
    }

    private var board: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: page.image)
                .resizable()
                .interpolation(.high)
            Overlay(segments: shown,
                    labels: shown.enumerated().map { doc.label(for: $1, number: $0 + 1) },
                    referenceID: page.referenceID,
                    selectedID: doc.selectedSegmentID,
                    activeHandle: doc.selectedHandle,
                    scale: doc.zoom)
        }
        .frame(width: boardSize.width, height: boardSize.height)
        .coordinateSpace(.named(Self.space))
        .contentShape(Rectangle())
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
        let delta: CGPoint
        switch press.key {
        case .upArrow: delta = CGPoint(x: 0, y: -step)
        case .downArrow: delta = CGPoint(x: 0, y: step)
        case .leftArrow: delta = CGPoint(x: -step, y: 0)
        default: delta = CGPoint(x: step, y: 0)
        }
        doc.nudge(dx: delta.x, dy: delta.y, wholeLine: press.modifiers.contains(.option))
        return .handled
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

    private var tolerance: Double { 10 / doc.zoom }

    /// Only the selected line offers handles — the one already showing the large dots.
    private func begin(at point: CGPoint) -> Grab {
        let selected = page.segments.filter { $0.id == doc.selectedSegmentID }
        guard let hit = handleHit(in: selected, near: point, tolerance: tolerance),
              let held = selected.first
        else { return .create(point) }
        doc.selectedHandle = hit.handle
        return .move(id: hit.id, handle: hit.handle,
                     anchor: hit.handle == .start ? held.end : held.start)
    }

    private func segment(for grab: Grab, at point: CGPoint) -> Segment? {
        let locked = NSEvent.modifierFlags.contains(.shift)
        switch grab {
        case .create(let origin):
            return Segment(start: origin, end: axisLocked(origin, point, locked: locked))
        case .move(let id, let handle, let anchor):
            let moved = axisLocked(anchor, point, locked: locked)
            let held = page.segments.first { $0.id == id }
            return handle == .start
                ? Segment(id: id, start: moved, end: anchor, name: held?.name ?? "")
                : Segment(id: id, start: anchor, end: moved, name: held?.name ?? "")
        }
    }

    private func commit(_ segment: Segment, for grab: Grab) {
        switch grab {
        case .create:
            doc.add(segment)
            doc.selectedHandle = .end
        case .move:
            doc.replace(segment)
        }
    }

    private func select(at point: CGPoint) {
        doc.selectedSegmentID = segmentHit(in: page.segments, near: point, tolerance: tolerance)
        guard let hit = doc.selectedSegment else { return }
        let toStart = hypot(point.x - hit.start.x, point.y - hit.start.y)
        let toEnd = hypot(point.x - hit.end.x, point.y - hit.end.y)
        doc.selectedHandle = toStart < toEnd ? .start : .end
    }
}
