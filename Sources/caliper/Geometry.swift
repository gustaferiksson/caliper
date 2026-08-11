import CoreGraphics

/// Maps between image points and view points for an aspect-fit, centred image.
struct Fit {
    let scale: CGFloat
    let origin: CGPoint

    init(image: CGSize, into view: CGSize) {
        scale = min(view.width / image.width, view.height / image.height)
        origin = CGPoint(x: (view.width - image.width * scale) / 2,
                         y: (view.height - image.height * scale) / 2)
    }

    func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale)
    }

    func toImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale)
    }
}

/// Shift locks the line to the dominant axis — dead horizontal or dead vertical.
func axisLocked(_ start: CGPoint, _ end: CGPoint, locked: Bool) -> CGPoint {
    guard locked else { return end }
    return abs(end.x - start.x) >= abs(end.y - start.y)
        ? CGPoint(x: end.x, y: start.y)
        : CGPoint(x: start.x, y: end.y)
}
