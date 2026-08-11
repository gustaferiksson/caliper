import AppKit
import SwiftUI

struct CanvasView: View {
    @Bindable var doc: Document
    @State private var draft: Segment?

    var body: some View {
        GeometryReader { geo in
            if let image = doc.image, geo.size.width > 0, geo.size.height > 0 {
                let fit = Fit(image: image.size, into: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: image.size.width * fit.scale,
                               height: image.size.height * fit.scale)
                        .offset(x: fit.origin.x, y: fit.origin.y)
                    Canvas { ctx, _ in draw(ctx, fit: fit) }
                }
                .contentShape(Rectangle())
                .gesture(drag(fit: fit))
            } else {
                placeholder
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            doc.open(url)
            return true
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("Drop an image here").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func drag(fit: Fit) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { draft = segment($0, fit: fit) }
            .onEnded { value in
                doc.commit(segment(value, fit: fit))
                draft = nil
            }
    }

    private func segment(_ value: DragGesture.Value, fit: Fit) -> Segment {
        let end = axisLocked(value.startLocation, value.location,
                             locked: NSEvent.modifierFlags.contains(.shift))
        return Segment(start: fit.toImage(value.startLocation), end: fit.toImage(end))
    }

    private func draw(_ ctx: GraphicsContext, fit: Fit) {
        if let calibration = doc.calibration {
            stroke(ctx, calibration, fit: fit, color: .orange, label: doc.calibrationLabel)
        }
        for segment in doc.segments {
            stroke(ctx, segment, fit: fit, color: .accentColor, label: doc.label(for: segment))
        }
        if let draft {
            let color: Color = doc.tool == .calibrate ? .orange : .accentColor
            stroke(ctx, draft, fit: fit, color: color.opacity(0.6), label: doc.label(for: draft))
        }
    }

    private func stroke(_ ctx: GraphicsContext, _ segment: Segment, fit: Fit,
                        color: Color, label: String) {
        let a = fit.toView(segment.start)
        let b = fit.toView(segment.end)
        var line = Path()
        line.move(to: a)
        line.addLine(to: b)
        ctx.stroke(line, with: .color(.black.opacity(0.55)), lineWidth: 4)
        ctx.stroke(line, with: .color(color), lineWidth: 2)
        for cap in [a, b] {
            let dot = CGRect(x: cap.x - 3, y: cap.y - 3, width: 6, height: 6)
            ctx.fill(Path(ellipseIn: dot), with: .color(color))
        }

        let text = ctx.resolve(Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white))
        let size = text.measure(in: CGSize(width: 240, height: 40))
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let box = CGRect(x: mid.x - size.width / 2 - 5, y: mid.y - size.height / 2 - 3,
                         width: size.width + 10, height: size.height + 6)
        ctx.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(.black.opacity(0.75)))
        ctx.draw(text, at: mid, anchor: .center)
    }
}
