import AppKit
import PDFKit

enum Loader {
    /// PDF pages keep their point size as the measurement space, rendered oversampled so zoom stays sharp.
    private static let renderScale = 3.0

    static func pages(from url: URL) -> [Page] {
        guard url.pathExtension.lowercased() == "pdf" else { return imagePage(from: url) }
        return pdfPages(from: url)
    }

    private static func imagePage(from url: URL) -> [Page] {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0
        else { return [] }
        return [Page(name: url.lastPathComponent, image: image)]
    }

    private static func pdfPages(from url: URL) -> [Page] {
        guard let pdf = PDFDocument(url: url) else { return [] }
        return (0..<pdf.pageCount).compactMap { index in
            guard let page = pdf.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { return nil }
            let render = CGSize(width: bounds.width * renderScale, height: bounds.height * renderScale)
            let image = page.thumbnail(of: render, for: .mediaBox)
            image.size = bounds.size
            let name = pdf.pageCount == 1
                ? url.lastPathComponent
                : "\(url.lastPathComponent) — page \(index + 1)"
            return Page(name: name, image: image)
        }
    }
}
