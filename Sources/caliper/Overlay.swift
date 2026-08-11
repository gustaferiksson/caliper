import SwiftUI

/// The measurement drawing, shared by the canvas and by export so both agree.
struct Overlay: View {
    let segments: [Segment]
    let labels: [String]
    let referenceID: Segment.ID?
    let selectedID: Segment.ID?
    let activeHandle: Handle
    let hovered: Grip?
    let scale: Double

    struct Grip: Equatable {
        let id: Segment.ID
        let handle: Handle
    }

    /// Handles keep one size on screen at every zoom.
    private static let tickLength: CGFloat = 5
    private static let ringRadius: CGFloat = 6
    private static let hoverRadius: CGFloat = 8
    private static let captionGap: CGFloat = 6

    var body: some View {
        Canvas { ctx, _ in
            for (index, segment) in segments.enumerated() {
                stroke(ctx, segment, label: labels.indices.contains(index) ? labels[index] : "")
            }
        }
    }

    private func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scale, y: p.y * scale)
    }

    private func stroke(_ ctx: GraphicsContext, _ segment: Segment, label: String) {
        let isSelected = segment.id == selectedID
        let color: Color = segment.id == referenceID ? .orange : .accentColor
        let a = point(segment.start)
        let b = point(segment.end)
        let normal = perpendicular(from: a, to: b)

        var body = Path()
        body.move(to: a)
        body.addLine(to: b)
        // Rings replace the ticks on the selected line, or the two collide.
        if !isSelected {
            for cap in [a, b] {
                body.move(to: CGPoint(x: cap.x - normal.x * Self.tickLength,
                                      y: cap.y - normal.y * Self.tickLength))
                body.addLine(to: CGPoint(x: cap.x + normal.x * Self.tickLength,
                                         y: cap.y + normal.y * Self.tickLength))
            }
        }
        ctx.stroke(body, with: .color(.black.opacity(0.55)), lineWidth: isSelected ? 6 : 4)
        ctx.stroke(body, with: .color(color), lineWidth: isSelected ? 3.5 : 2)

        if isSelected {
            for (handle, cap) in [(Handle.start, a), (Handle.end, b)] {
                grip(ctx, at: cap, color: color, handle: handle, on: segment.id)
            }
        }
        caption(ctx, label: label, between: a, and: b, normal: normal)
    }

    private func perpendicular(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.001)
        return CGPoint(x: -dy / length, y: dx / length)
    }

    /// An open ring, so the measured point stays visible under the pointer.
    private func grip(_ ctx: GraphicsContext, at p: CGPoint, color: Color,
                      handle: Handle, on id: Segment.ID) {
        let isHovered = hovered == Grip(id: id, handle: handle)
        let isActive = handle == activeHandle
        let radius = isHovered ? Self.hoverRadius : Self.ringRadius
        let ring = Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius,
                                          width: radius * 2, height: radius * 2))
        ctx.stroke(ring, with: .color(.black.opacity(0.55)), lineWidth: 4)
        ctx.stroke(ring, with: .color(.white), lineWidth: 2.5)
        ctx.stroke(ring, with: .color(color), lineWidth: isHovered ? 2.5 : 1.5)
        guard isActive else { return }
        let pip = CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)
        ctx.fill(Path(ellipseIn: pip), with: .color(color))
    }

    /// The caption sits beside the line, never on it — you must see what you measured.
    /// Pushing it out by the box's own extent along the normal keeps sloped lines clear.
    private func caption(_ ctx: GraphicsContext, label: String,
                         between a: CGPoint, and b: CGPoint, normal: CGPoint) {
        guard !label.isEmpty else { return }
        let text = ctx.resolve(Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white))
        let size = text.measure(in: CGSize(width: 320, height: 40))
        let half = CGSize(width: size.width / 2 + 5, height: size.height / 2 + 3)
        let side = normal.y > 0 ? CGPoint(x: -normal.x, y: -normal.y) : normal
        let reach = abs(side.x) * half.width + abs(side.y) * half.height + Self.captionGap
        let anchor = CGPoint(x: (a.x + b.x) / 2 + side.x * reach,
                             y: (a.y + b.y) / 2 + side.y * reach)
        let box = CGRect(x: anchor.x - half.width, y: anchor.y - half.height,
                         width: half.width * 2, height: half.height * 2)
        ctx.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(.black.opacity(0.75)))
        ctx.draw(text, at: anchor, anchor: .center)
    }
}
