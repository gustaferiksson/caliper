import AppKit
import Observation

struct Segment: Identifiable, Hashable {
    let id = UUID()
    var start: CGPoint
    var end: CGPoint

    var length: Double { hypot(end.x - start.x, end.y - start.y) }
}

enum Tool: String, CaseIterable, Identifiable {
    case calibrate = "Calibrate"
    case measure = "Measure"

    var id: String { rawValue }
    var symbol: String { self == .calibrate ? "ruler" : "pencil.and.outline" }
}

@Observable
final class Document {
    var image: NSImage?
    var tool: Tool = .calibrate
    var calibration: Segment?
    var knownLength = 100.0
    var unit = "mm"
    var segments: [Segment] = []

    var unitsPerPoint: Double? {
        guard let calibration, calibration.length > 0, knownLength > 0 else { return nil }
        return knownLength / calibration.length
    }

    var isCalibrated: Bool { unitsPerPoint != nil }

    var calibrationLabel: String {
        String(format: "%g %@", knownLength, unit)
    }

    func label(for segment: Segment) -> String {
        guard let unitsPerPoint else { return String(format: "%.0f px", segment.length) }
        return String(format: "%.2f %@", segment.length * unitsPerPoint, unit)
    }

    func commit(_ segment: Segment) {
        guard segment.length > 2 else { return }
        if tool == .calibrate {
            calibration = segment
        } else {
            segments.append(segment)
        }
    }

    func remove(_ segment: Segment) {
        segments.removeAll { $0.id == segment.id }
    }

    func open(_ url: URL) {
        guard let opened = NSImage(contentsOf: url), opened.size.width > 0 else { return }
        image = opened
        calibration = nil
        segments = []
    }
}
