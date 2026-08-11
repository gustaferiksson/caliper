import SwiftUI

/// The measurement drawing, shared by the canvas and by export so both agree.
struct Overlay: View {
    let segments: [Segment]
    let labels: [String]
    let referenceID: Segment.ID?
    let selectedID: Segment.ID?
    let activeHandle: Handle
    let scale: Double

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

        var line = Path()
        line.move(to: a)
        line.addLine(to: b)
        ctx.stroke(line, with: .color(.black.opacity(0.55)), lineWidth: isSelected ? 5 : 4)
        ctx.stroke(line, with: .color(color), lineWidth: isSelected ? 3 : 2)

        for (handle, cap) in [(Handle.start, a), (Handle.end, b)] {
            let radius: CGFloat = isSelected ? 5 : 3
            let dot = CGRect(x: cap.x - radius, y: cap.y - radius,
                             width: radius * 2, height: radius * 2)
            let isActive = isSelected && handle == activeHandle
            ctx.fill(Path(ellipseIn: dot), with: .color(isActive ? color : (isSelected ? .white : color)))
            if isSelected {
                ctx.stroke(Path(ellipseIn: dot), with: .color(isActive ? .white : color), lineWidth: 2)
            }
        }

        guard !label.isEmpty else { return }
        let text = ctx.resolve(Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white))
        let size = text.measure(in: CGSize(width: 320, height: 40))
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let box = CGRect(x: mid.x - size.width / 2 - 5, y: mid.y - size.height / 2 - 3,
                         width: size.width + 10, height: size.height + 6)
        ctx.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(.black.opacity(0.75)))
        ctx.draw(text, at: mid, anchor: .center)
    }
}
