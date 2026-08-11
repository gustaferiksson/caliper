import AppKit
import SwiftUI

struct CanvasView: View {
    @Bindable var doc: Document
    let page: Page

    @State private var grab: Grab?
    @State private var live: Segment?
    @State private var zoomBase: Double?

    private enum Grab {
        case create(CGPoint)
        case move(id: Segment.ID, handle: Handle, anchor: CGPoint)
    }

    private static let space = "board"

    private var boardSize: CGSize {
        CGSize(width: page.image.size.width * doc.zoom, height: page.image.size.height * doc.zoom)
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
            Canvas { ctx, _ in draw(ctx) }
        }
        .frame(width: boardSize.width, height: boardSize.height)
        .coordinateSpace(.named(Self.space))
        .contentShape(Rectangle())
        .gesture(drag)
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

    private func begin(at point: CGPoint) -> Grab {
        guard let hit = handleHit(in: page.segments, near: point, tolerance: tolerance),
              let held = page.segments.first(where: { $0.id == hit.id })
        else { return .create(point) }
        doc.selectedSegmentID = hit.id
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
            return handle == .start
                ? Segment(id: id, start: moved, end: anchor)
                : Segment(id: id, start: anchor, end: moved)
        }
    }

    private func commit(_ segment: Segment, for grab: Grab) {
        switch grab {
        case .create: doc.add(segment)
        case .move: doc.replace(segment)
        }
    }

    private func select(at point: CGPoint) {
        doc.selectedSegmentID = segmentHit(in: page.segments, near: point, tolerance: tolerance)
    }

    private func draw(_ ctx: GraphicsContext) {
        var shown = page.segments
        if let live {
            if let index = shown.firstIndex(where: { $0.id == live.id }) {
                shown[index] = live
            } else {
                shown.append(live)
            }
        }
        for segment in shown { stroke(ctx, segment) }
    }

    private func stroke(_ ctx: GraphicsContext, _ segment: Segment) {
        let isReference = segment.id == page.referenceID
        let isSelected = segment.id == doc.selectedSegmentID
        let color: Color = isReference ? .orange : .accentColor
        let a = viewPoint(segment.start)
        let b = viewPoint(segment.end)

        var line = Path()
        line.move(to: a)
        line.addLine(to: b)
        ctx.stroke(line, with: .color(.black.opacity(0.55)), lineWidth: isSelected ? 5 : 4)
        ctx.stroke(line, with: .color(color), lineWidth: isSelected ? 3 : 2)

        let radius: CGFloat = isSelected ? 5 : 3
        for cap in [a, b] {
            let dot = CGRect(x: cap.x - radius, y: cap.y - radius, width: radius * 2, height: radius * 2)
            ctx.fill(Path(ellipseIn: dot), with: .color(isSelected ? .white : color))
            if isSelected { ctx.stroke(Path(ellipseIn: dot), with: .color(color), lineWidth: 2) }
        }

        let text = ctx.resolve(Text(doc.label(for: segment))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white))
        let size = text.measure(in: CGSize(width: 240, height: 40))
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let box = CGRect(x: mid.x - size.width / 2 - 5, y: mid.y - size.height / 2 - 3,
                         width: size.width + 10, height: size.height + 6)
        ctx.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(.black.opacity(0.75)))
        ctx.draw(text, at: mid, anchor: .center)
    }

    private func viewPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * doc.zoom, y: p.y * doc.zoom)
    }
}
