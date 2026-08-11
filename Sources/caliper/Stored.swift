import CoreGraphics
import Foundation

/// The saved payload. One per source file, covering every page that file contributed.
struct Stored: Codable {
    struct Line: Codable {
        var x1: Double
        var y1: Double
        var x2: Double
        var y2: Double
        var name: String?
    }

    /// A lender in another file, named so it can be relinked when both files are open.
    struct Lender: Codable {
        var file: String
        var page: Int
    }

    struct Sheet: Codable {
        var page: Int
        var lines: [Line]
        var reference: Int?
        var referenceLength: Double
        var lender: Lender?
    }

    var version = 1
    var unit: String
    var sheets: [Sheet]
}

extension Stored {
    static func payload(for pages: [Page], unit: String, lender: (Page.ID) -> Lender?) -> Stored {
        Stored(unit: unit, sheets: pages.map { page in
            Sheet(page: page.pageIndex,
                  lines: page.segments.map {
                      Line(x1: $0.start.x, y1: $0.start.y, x2: $0.end.x, y2: $0.end.y,
                           name: $0.name.isEmpty ? nil : $0.name)
                  },
                  reference: page.segments.firstIndex { $0.id == page.referenceID },
                  referenceLength: page.referenceLength,
                  lender: page.scaleSource.flatMap(lender))
        })
    }

    /// Fills the freshly loaded pages and reports the lenders that still need resolving.
    func apply(to pages: inout [Page]) -> [Page.ID: Lender] {
        var pending: [Page.ID: Lender] = [:]
        for sheet in sheets {
            guard let index = pages.firstIndex(where: { $0.pageIndex == sheet.page }) else { continue }
            pages[index].segments = sheet.lines.map {
                Segment(start: CGPoint(x: $0.x1, y: $0.y1), end: CGPoint(x: $0.x2, y: $0.y2),
                        name: $0.name ?? "")
            }
            pages[index].referenceLength = sheet.referenceLength
            if let reference = sheet.reference, pages[index].segments.indices.contains(reference) {
                pages[index].referenceID = pages[index].segments[reference].id
            }
            if let lender = sheet.lender { pending[pages[index].id] = lender }
        }
        return pending
    }
}
