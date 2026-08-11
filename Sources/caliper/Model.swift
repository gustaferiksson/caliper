import AppKit
import Observation
import SwiftUI

struct Segment: Identifiable, Hashable {
    let id: UUID
    var start: CGPoint
    var end: CGPoint
    var name: String
    /// Signed distance the dimension line is pushed off the measured points.
    var offset: Double

    init(id: UUID = UUID(), start: CGPoint, end: CGPoint, name: String = "", offset: Double = 0) {
        self.id = id
        self.start = start
        self.end = end
        self.name = name
        self.offset = offset
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
    /// nil means the whole line is chosen rather than one of its ends.
    var selectedHandle: Handle?
    var unit = "mm" { didSet { if unit != oldValue { dirty = true } } }
    var lineColor = Color.defaultMeasurement { didSet { if lineColor != oldValue { dirty = true } } }
    var zoom = 1.0
    var viewport = CGSize.zero
    var saveReport: String?
    private(set) var dirty = false

    private var undoStack: [[Page]] = []
    private var redoStack: [[Page]] = []
    private var nudged: Segment.ID?
    private static let historyLimit = 100
    private static let minimumLength = 2.0

    var page: Page? { pages.first { $0.id == selectedPageID } }
    var selectedSegment: Segment? {
        page?.segments.first { $0.id == selectedSegmentID }
    }

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

    func measurement(for segment: Segment, on page: Page) -> String {
        guard let factor = scale(of: page) else {
            return String(format: "%.0f px", segment.length)
        }
        return "\(Self.rounded(segment.length * factor)) \(unit)"
    }

    func measurement(for segment: Segment) -> String {
        guard let page else { return String(format: "%.0f px", segment.length) }
        return measurement(for: segment, on: page)
    }

    /// Name and value only — the number rides its own badge on the canvas.
    func caption(for segment: Segment, on page: Page) -> String {
        [segment.name, measurement(for: segment, on: page)]
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
    }

    func caption(for segment: Segment) -> String {
        guard let page else { return measurement(for: segment) }
        return caption(for: segment, on: page)
    }

    func label(for segment: Segment, number: Int, on page: Page) -> String {
        "\(number)  \(caption(for: segment, on: page))"
    }

    func label(for segment: Segment, number: Int) -> String {
        guard let page else { return measurement(for: segment) }
        return label(for: segment, number: number, on: page)
    }

    /// Fewer decimals as the number grows, so metres and millimetres both read sanely.
    static func rounded(_ value: Double) -> String {
        let magnitude = abs(value)
        let places = magnitude >= 1000 ? 0 : (magnitude >= 100 ? 1 : (magnitude >= 1 ? 2 : 3))
        return String(format: "%.\(places)f", value)
    }

    var scaleReadout: String? {
        guard let page, let factor = scale(of: page) else { return nil }
        return "1 px = \(String(format: "%.4g", factor)) \(unit)"
    }

    /// A short reference multiplies its own placement error into every other line.
    var referenceWarning: String? {
        guard let page, let factor = scale(of: page), factor > 0 else { return nil }
        let lender = page.scaleSource.flatMap { id in pages.first { $0.id == id } } ?? page
        guard let reference = lender.reference else { return nil }
        if reference.length < 30 {
            return "The reference is only \(Int(reference.length)) px long. Draw it longer for accuracy."
        }
        guard let longest = page.segments.map(\.length).max(), longest > reference.length * 5 else {
            return nil
        }
        return "Some lines are over 5× the reference. Errors in the reference scale up."
    }

    func name(of id: Segment.ID) -> String {
        page?.segments.first { $0.id == id }?.name ?? ""
    }

    func setName(_ name: String, for id: Segment.ID) {
        mutate(undoable: false) { page in
            guard let index = page.segments.firstIndex(where: { $0.id == id }) else { return }
            page.segments[index].name = name
        }
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
                if let hex = stored.color, let restored = Color(hex: hex) { lineColor = restored }
            }
            loaded.append(contentsOf: fresh)
        }
        guard !loaded.isEmpty else { return }
        let wasDirty = dirty
        checkpoint()
        pages.append(contentsOf: loaded)
        relink(pending)
        selectedPageID = loaded.first?.id
        selectedSegmentID = nil
        fitZoom()
        dirty = wasDirty // opening a file is not an unsaved edit
    }

    func save() throws {
        for (url, group) in Dictionary(grouping: pages, by: \.source) {
            let payload = Stored.payload(for: group, unit: unit, color: lineColor.hex, lender: lender)
            try Metadata.write(payload, to: url)
        }
    }

    func saveNow() {
        do {
            try save()
            dirty = false
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

    /// Arrows move whatever is chosen: one handle, or the whole line.
    /// A run of presses on one line collapses into a single undo step.
    func nudge(dx: Double, dy: Double) {
        guard let id = selectedSegmentID else { return }
        let handle = selectedHandle
        mutate(undoable: nudged != id) { page in
            guard let index = page.segments.firstIndex(where: { $0.id == id }) else { return }
            if handle != .end {
                page.segments[index].start.x += dx
                page.segments[index].start.y += dy
            }
            if handle != .start {
                page.segments[index].end.x += dx
                page.segments[index].end.y += dy
            }
        }
        nudged = id
    }

    func closeCurrentFile() {
        guard let source = page?.source else { return }
        checkpoint()
        pages.removeAll { $0.source == source }
        repairSelection()
        fitZoom()
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
        dirty = true
    }

    private func checkpoint() {
        undoStack.append(pages)
        if undoStack.count > Self.historyLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        nudged = nil
        dirty = true
    }

    private func repairSelection() {
        nudged = nil
        if !pages.contains(where: { $0.id == selectedPageID }) {
            selectedPageID = pages.first?.id
        }
        if page?.segments.contains(where: { $0.id == selectedSegmentID }) != true {
            selectedSegmentID = nil
        }
        let live = Set(pages.map(\.id))
        for index in pages.indices where pages[index].scaleSource.map({ !live.contains($0) }) == true {
            pages[index].scaleSource = nil
        }
    }
}
