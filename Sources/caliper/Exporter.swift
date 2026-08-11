import AppKit
import PDFKit
import SwiftUI

enum ExportError: LocalizedError {
    case render
    case write(String)

    var errorDescription: String? {
        switch self {
        case .render: return "Could not render the measurements."
        case .write(let name): return "Could not write \(name)."
        }
    }
}

/// Images get the labels burned in. PDFs get real line annotations instead, so
/// other readers list them as measurements rather than flattened pixels.
@MainActor
enum Exporter {
    static func suggestedName(for page: Page) -> String {
        let base = page.source.deletingPathExtension().lastPathComponent
        return "\(base)-measured.\(isPDF(page) ? "pdf" : "png")"
    }

    static func isPDF(_ page: Page) -> Bool {
        page.source.pathExtension.lowercased() == "pdf"
    }

    static func export(pages: [Page], labels: [Page.ID: [String]], to url: URL) throws {
        guard let first = pages.first else { throw ExportError.render }
        if isPDF(first) {
            try exportPDF(pages: pages, labels: labels, to: url)
        } else {
            try exportImage(page: first, labels: labels[first.id] ?? [], to: url)
        }
    }

    private static func exportImage(page: Page, labels: [String], to url: URL) throws {
        let size = page.image.size
        let sheet = ZStack(alignment: .topLeading) {
            Image(nsImage: page.image).resizable().interpolation(.high)
            Overlay(segments: page.segments, labels: labels, referenceID: page.referenceID,
                    selectedID: nil, activeHandle: .end, scale: 1)
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = pixelScale(of: page.image)
        guard let rendered = renderer.cgImage else { throw ExportError.render }
        let rep = NSBitmapImageRep(cgImage: rendered)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.render
        }
        try data.write(to: url)
    }

    private static func pixelScale(of image: NSImage) -> CGFloat {
        guard let rep = image.representations.first, image.size.width > 0 else { return 2 }
        return max(1, CGFloat(rep.pixelsWide) / image.size.width)
    }

    private static func exportPDF(pages: [Page], labels: [Page.ID: [String]], to url: URL) throws {
        guard let source = pages.first?.source, let pdf = PDFDocument(url: source) else {
            throw ExportError.write(url.lastPathComponent)
        }
        for page in pages {
            guard let sheet = pdf.page(at: page.pageIndex) else { continue }
            let box = sheet.bounds(for: .mediaBox)
            for (index, segment) in page.segments.enumerated() {
                let label = labels[page.id]?.indices.contains(index) == true
                    ? labels[page.id]![index] : ""
                add(segment, label: label,
                    isReference: segment.id == page.referenceID, to: sheet, box: box)
            }
        }
        guard pdf.write(to: url) else { throw ExportError.write(url.lastPathComponent) }
    }

    /// Image space is top-left with y down; PDF space is bottom-left with y up.
    private static func pdfPoint(_ p: CGPoint, box: CGRect) -> CGPoint {
        CGPoint(x: box.minX + p.x, y: box.maxY - p.y)
    }

    /// A caption centred on a line near the edge would otherwise hang off the page.
    private static func clamped(_ rect: CGRect, into box: CGRect) -> CGRect {
        CGRect(x: min(max(rect.minX, box.minX), max(box.minX, box.maxX - rect.width)),
               y: min(max(rect.minY, box.minY), max(box.minY, box.maxY - rect.height)),
               width: min(rect.width, box.width),
               height: min(rect.height, box.height))
    }

    private static func add(_ segment: Segment, label: String, isReference: Bool,
                            to sheet: PDFPage, box: CGRect) {
        let a = pdfPoint(segment.start, box: box)
        let b = pdfPoint(segment.end, box: box)
        let colour = isReference ? NSColor.systemOrange : NSColor.systemBlue

        let line = PDFAnnotation(bounds: box, forType: .line, withProperties: nil)
        line.startPoint = a
        line.endPoint = b
        line.color = colour
        line.contents = label
        line.border = PDFBorder()
        line.border?.lineWidth = 2
        sheet.addAnnotation(line)

        guard !label.isEmpty else { return }
        let width = max(60, Double(label.count) * 7)
        let caption = clamped(CGRect(x: (a.x + b.x) / 2 - width / 2, y: (a.y + b.y) / 2 - 9,
                                     width: width, height: 18), into: box)
        let text = PDFAnnotation(bounds: caption, forType: .freeText, withProperties: nil)
        text.contents = label
        text.font = .systemFont(ofSize: 11, weight: .semibold)
        text.fontColor = .white
        text.color = NSColor.black.withAlphaComponent(0.75)
        text.alignment = .center
        sheet.addAnnotation(text)
    }
}
