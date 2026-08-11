import SwiftUI

/// The measurement drawing, shared by the canvas and by export so both agree.
struct Overlay: View {
    let segments: [Segment]
    let captions: [String]
    let referenceID: Segment.ID?
    let selectedID: Segment.ID?
    let activeHandle: Handle?
    let hovered: Grip?
    let tint: Color
    let scale: Double

    struct Grip: Equatable {
        let id: Segment.ID
        let handle: Handle
    }

    /// Everything here keeps one size on screen at every zoom. Selection changes
    /// shade, never size, so nothing shifts under the pointer.
    private static let lineWidth: CGFloat = 1.5
    private static let tickLength: CGFloat = 5
    private static let handleSide: CGFloat = 11
    private static let witnessGap: CGFloat = 3
    private static let witnessOvershoot: CGFloat = 4
    private static let captionGap: CGFloat = 6
    private static let badgeSide: CGFloat = 16
    private static let badgeGap: CGFloat = 4
    private static let selectedShade = 0.35
    private static let hoveredShade = 0.55

    var body: some View {
        Canvas { ctx, _ in
            for (index, segment) in segments.enumerated() {
                stroke(ctx, segment, number: index + 1,
                       text: captions.indices.contains(index) ? captions[index] : "")
            }
        }
    }

    private func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scale, y: p.y * scale)
    }

    private func stroke(_ ctx: GraphicsContext, _ segment: Segment, number: Int, text: String) {
        let isSelected = segment.id == selectedID
        let base: Color = segment.id == referenceID ? .reference : tint
        let color = isSelected ? base.darkened(by: Self.selectedShade) : base

        let a = point(segment.start)
        let b = point(segment.end)
        let across = perpendicular(from: a, to: b)
        let reach = abs(segment.offset) * scale
        let out = segment.offset >= 0 ? across : CGPoint(x: -across.x, y: -across.y)
        let head = CGPoint(x: a.x + out.x * reach, y: a.y + out.y * reach)
        let tail = CGPoint(x: b.x + out.x * reach, y: b.y + out.y * reach)

        if reach > 1 {
            witness(ctx, from: [a, b], along: out, reach: reach, color: color,
                    weight: isSelected ? 2 : Self.lineWidth)
        }

        var body = Path()
        body.move(to: head)
        body.addLine(to: tail)
        // Ticks are collinear with the witness lines, so an offset line would merge
        // the two into an L. Offset: witness marks the end. Selected: the square does.
        if reach <= 1 && !isSelected {
            for cap in [head, tail] {
                body.move(to: CGPoint(x: cap.x - across.x * Self.tickLength,
                                      y: cap.y - across.y * Self.tickLength))
                body.addLine(to: CGPoint(x: cap.x + across.x * Self.tickLength,
                                         y: cap.y + across.y * Self.tickLength))
            }
        }
        ctx.stroke(body, with: .color(color), lineWidth: Self.lineWidth)

        if isSelected {
            let along = CGPoint(x: across.y, y: -across.x)
            for (handle, cap) in [(Handle.start, a), (Handle.end, b)] {
                grip(ctx, at: cap, base: base, handle: handle, on: segment.id,
                     along: along, across: across)
            }
        }
        caption(ctx, number: number, text: text, between: head, and: tail,
                normal: across, color: color)
    }

    /// The measured point keeps a full-weight flat end. Only the run out to the
    /// moved dimension line goes slim.
    private func witness(_ ctx: GraphicsContext, from feet: [CGPoint], along out: CGPoint,
                         reach: CGFloat, color: Color, weight: CGFloat) {
        let stub = min(Self.tickLength, reach * 0.4)
        var ends = Path()
        var runs = Path()
        for foot in feet {
            ends.move(to: CGPoint(x: foot.x - out.x * stub, y: foot.y - out.y * stub))
            ends.addLine(to: CGPoint(x: foot.x + out.x * stub, y: foot.y + out.y * stub))
            runs.move(to: CGPoint(x: foot.x + out.x * stub, y: foot.y + out.y * stub))
            runs.addLine(to: CGPoint(x: foot.x + out.x * (reach + Self.witnessOvershoot),
                                     y: foot.y + out.y * (reach + Self.witnessOvershoot)))
        }
        ctx.stroke(ends, with: .color(color), lineWidth: weight)
        ctx.stroke(runs, with: .color(color.opacity(0.45)), lineWidth: 1)
    }

    private func perpendicular(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.001)
        return CGPoint(x: -dy / length, y: dx / length)
    }

    /// An open square turned to the line, so its end edges read as the flat end and
    /// the measured point stays visible under the pointer.
    private func grip(_ ctx: GraphicsContext, at p: CGPoint, base: Color,
                      handle: Handle, on id: Segment.ID, along: CGPoint, across: CGPoint) {
        let isHovered = hovered == Grip(id: id, handle: handle)
        let color = base.darkened(by: isHovered ? Self.hoveredShade : Self.selectedShade)
        let half = Self.handleSide / 2
        func corner(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: p.x + along.x * half * u + across.x * half * v,
                    y: p.y + along.y * half * u + across.y * half * v)
        }
        var box = Path()
        box.move(to: corner(1, 1))
        box.addLine(to: corner(1, -1))
        box.addLine(to: corner(-1, -1))
        box.addLine(to: corner(-1, 1))
        box.closeSubpath()
        ctx.stroke(box, with: .color(color), lineWidth: Self.lineWidth)
        guard handle == activeHandle else { return }
        ctx.fill(Path(CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(color))
    }

    /// The number rides its own badge outside the value box, or it reads as part of
    /// the measurement. The pair sits beside the line, never across it.
    private func caption(_ ctx: GraphicsContext, number: Int, text: String,
                         between a: CGPoint, and b: CGPoint, normal: CGPoint, color: Color) {
        let index = ctx.resolve(Text("\(number)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white))
        let value = text.isEmpty ? nil : ctx.resolve(Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white))
        let valueSize = value?.measure(in: CGSize(width: 320, height: 40)) ?? .zero
        let boxWidth = value == nil ? 0 : valueSize.width + 10
        let height = max(Self.badgeSide, value == nil ? 0 : valueSize.height + 6)
        let width = Self.badgeSide + (boxWidth > 0 ? Self.badgeGap + boxWidth : 0)

        let side = normal.y > 0 ? CGPoint(x: -normal.x, y: -normal.y) : normal
        let reach = abs(side.x) * width / 2 + abs(side.y) * height / 2 + Self.captionGap
        let centre = CGPoint(x: (a.x + b.x) / 2 + side.x * reach,
                             y: (a.y + b.y) / 2 + side.y * reach)
        let left = centre.x - width / 2

        let badge = CGRect(x: left, y: centre.y - Self.badgeSide / 2,
                           width: Self.badgeSide, height: Self.badgeSide)
        ctx.fill(Path(roundedRect: badge, cornerRadius: 3), with: .color(color))
        ctx.draw(index, at: CGPoint(x: badge.midX, y: badge.midY), anchor: .center)

        guard let value else { return }
        let box = CGRect(x: left + Self.badgeSide + Self.badgeGap, y: centre.y - height / 2,
                         width: boxWidth, height: height)
        ctx.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(.black.opacity(0.75)))
        ctx.draw(value, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
    }
}
