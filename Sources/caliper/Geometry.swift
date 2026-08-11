import CoreGraphics

enum Handle {
    case start
    case end
}

/// Shift locks the line to the dominant axis — dead horizontal or dead vertical.
func axisLocked(_ start: CGPoint, _ end: CGPoint, locked: Bool) -> CGPoint {
    guard locked else { return end }
    return abs(end.x - start.x) >= abs(end.y - start.y)
        ? CGPoint(x: end.x, y: start.y)
        : CGPoint(x: start.x, y: end.y)
}

func distance(from p: CGPoint, to segment: Segment) -> Double {
    let dx = segment.end.x - segment.start.x
    let dy = segment.end.y - segment.start.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return hypot(p.x - segment.start.x, p.y - segment.start.y) }
    let along = ((p.x - segment.start.x) * dx + (p.y - segment.start.y) * dy) / lengthSquared
    let clamped = max(0, min(1, along))
    return hypot(p.x - (segment.start.x + clamped * dx), p.y - (segment.start.y + clamped * dy))
}

func handleHit(in segments: [Segment], near p: CGPoint, tolerance: Double)
    -> (id: Segment.ID, handle: Handle)? {
    var best: (id: Segment.ID, handle: Handle, distance: Double)?
    for segment in segments {
        for (handle, point) in [(Handle.start, segment.start), (Handle.end, segment.end)] {
            let reach = Double(hypot(p.x - point.x, p.y - point.y))
            guard reach <= tolerance, reach < (best?.distance ?? .greatestFiniteMagnitude) else {
                continue
            }
            best = (segment.id, handle, reach)
        }
    }
    guard let best else { return nil }
    return (best.id, best.handle)
}

/// Reversed so the most recent line wins where two overlap.
func segmentHit(in segments: [Segment], near p: CGPoint, tolerance: Double) -> Segment.ID? {
    segments.reversed().first { distance(from: p, to: $0) <= tolerance }?.id
}
