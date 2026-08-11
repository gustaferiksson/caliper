import AppKit
import Observation

struct Segment: Identifiable, Hashable {
    let id: UUID
    var start: CGPoint
    var end: CGPoint

    init(id: UUID = UUID(), start: CGPoint, end: CGPoint) {
        self.id = id
        self.start = start
        self.end = end
    }

    var length: Double { hypot(end.x - start.x, end.y - start.y) }
    var midpoint: CGPoint { CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2) }
}

struct Page: Identifiable {
    let id = UUID()
    let name: String
    let image: NSImage
    let source: URL
    let pageIndex: Int
    var segments: [Segment] = []
    var referenceID: Segment.ID?
    var referenceLength = 100.0
    var scaleSource: Page.ID?

    var reference: Segment? { segments.first { $0.id == referenceID } }

    /// Only a page holding its own reference can lend a scale, so resolution never chains.
    var ownScale: Double? {
        guard scaleSource == nil, let reference, reference.length > 0, referenceLength > 0
        else { return nil }
        return referenceLength / reference.length
    }
}

@Observable
final class Document {
    var pages: [Page] = []
    var selectedPageID: Page.ID?
    var selectedSegmentID: Segment.ID?
    var unit = "mm"
    var zoom = 1.0
    var viewport = CGSize.zero
    var saveReport: String?

    private var undoStack: [[Page]] = []
    private var redoStack: [[Page]] = []
    private static let historyLimit = 100
    private static let minimumLength = 2.0

    var page: Page? { pages.first { $0.id == selectedPageID } }

    /// Not undoable — a text field would push a checkpoint per keystroke.
    var referenceLength: Double {
        get { page?.referenceLength ?? 0 }
        set { mutate(undoable: false) { $0.referenceLength = newValue } }
    }

    var scaleSource: Page.ID? {
        get { page?.scaleSource }
        set { mutate { $0.scaleSource = newValue } }
    }

    /// Pages the current one can borrow a scale from.
    var scaleLenders: [Page] {
        pages.filter { $0.id != selectedPageID && $0.ownScale != nil }
    }

    func scale(of page: Page) -> Double? {
        guard let source = page.scaleSource else { return page.ownScale }
        return pages.first { $0.id == source }?.ownScale
    }

    func measurement(for segment: Segment) -> String {
        guard let page, let factor = scale(of: page) else {
            return String(format: "%.0f px", segment.length)
        }
        return String(format: "%.2f %@", segment.length * factor, unit)
    }

    func label(for segment: Segment, number: Int) -> String {
        "\(number)  \(measurement(for: segment))"
    }

    func open(_ urls: [URL]) {
        var loaded: [Page] = []
        var pending: [Page.ID: Stored.Lender] = [:]
        for url in urls {
            var fresh = Loader.pages(from: url)
            guard !fresh.isEmpty else { continue }
            if let stored = Metadata.read(from: url) {
                pending.merge(stored.apply(to: &fresh)) { first, _ in first }
                unit = stored.unit
            }
            loaded.append(contentsOf: fresh)
        }
        guard !loaded.isEmpty else { return }
        checkpoint()
        pages.append(contentsOf: loaded)
        relink(pending)
        selectedPageID = loaded.first?.id
        selectedSegmentID = nil
        fitZoom()
    }

    func save() throws {
        for (url, group) in Dictionary(grouping: pages, by: \.source) {
            try Metadata.write(Stored.payload(for: group, unit: unit, lender: lender), to: url)
        }
    }

    func saveNow() {
        do {
            try save()
            saveReport = "Saved into \(Set(pages.map(\.source)).count) file(s)."
        } catch {
            saveReport = error.localizedDescription
        }
    }

    private func lender(for id: Page.ID) -> Stored.Lender? {
        guard let source = pages.first(where: { $0.id == id }) else { return nil }
        return Stored.Lender(file: source.source.lastPathComponent, page: source.pageIndex)
    }

    private func relink(_ pending: [Page.ID: Stored.Lender]) {
        for (id, lender) in pending {
            guard let target = pages.first(where: {
                      $0.source.lastPathComponent == lender.file && $0.pageIndex == lender.page
                  }),
                  let index = pages.firstIndex(where: { $0.id == id })
            else { continue }
            pages[index].scaleSource = target.id
        }
    }

    func add(_ segment: Segment) {
        guard segment.length > Self.minimumLength else { return }
        mutate { $0.segments.append(segment) }
        selectedSegmentID = segment.id
    }

    func replace(_ segment: Segment) {
        guard segment.length > Self.minimumLength else { return }
        mutate { page in
            guard let index = page.segments.firstIndex(where: { $0.id == segment.id }) else { return }
            page.segments[index] = segment
        }
    }

    func remove(_ id: Segment.ID) {
        mutate { page in
            page.segments.removeAll { $0.id == id }
            if page.referenceID == id { page.referenceID = nil }
        }
        if selectedSegmentID == id { selectedSegmentID = nil }
    }

    func removeSelected() {
        guard let selectedSegmentID else { return }
        remove(selectedSegmentID)
    }

    func toggleReference(_ id: Segment.ID) {
        mutate { $0.referenceID = $0.referenceID == id ? nil : id }
    }

    func fitZoom() {
        guard let page, viewport.width > 0, viewport.height > 0 else { return }
        let size = page.image.size
        zoom = min(viewport.width / size.width, viewport.height / size.height)
    }

    func stepZoom(_ factor: Double) {
        zoom = min(max(zoom * factor, 0.05), 40)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(pages)
        pages = previous
        repairSelection()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(pages)
        pages = next
        repairSelection()
    }

    private func mutate(undoable: Bool = true, _ change: (inout Page) -> Void) {
        guard let index = pages.firstIndex(where: { $0.id == selectedPageID }) else { return }
        if undoable { checkpoint() }
        change(&pages[index])
    }

    private func checkpoint() {
        undoStack.append(pages)
        if undoStack.count > Self.historyLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func repairSelection() {
        if !pages.contains(where: { $0.id == selectedPageID }) {
            selectedPageID = pages.first?.id
        }
        guard let current = page, current.segments.contains(where: { $0.id == selectedSegmentID })
        else {
            selectedSegmentID = nil
            return
        }
    }
}
