import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let doc = Document()

    /// Measurements live only in memory until a save, so quitting dirty must ask.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard doc.dirty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Save measurements before quitting?"
        alert.informativeText = "Caliper writes them into the files you opened."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            doc.saveNow()
            return doc.dirty ? .terminateCancel : .terminateNow
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}

@main
struct CaliperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var doc: Document { delegate.doc }

    var body: some Scene {
        WindowGroup("Caliper") {
            ContentView(doc: doc)
        }
        .windowToolbarStyle(.unified)
        // Wide enough that the toolbar never collapses into the » overflow menu.
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save Measurements") { doc.saveNow() }
                    .keyboardShortcut("s")
                    .disabled(doc.pages.isEmpty)
                Button("Export…") { NotificationCenter.default.post(name: .caliperExport, object: nil) }
                    .keyboardShortcut("e")
                    .disabled(doc.page == nil)
                Divider()
                // Falls through to the window when nothing is open, so ⌘W still closes it.
                Button("Close File") {
                    if doc.page == nil {
                        NSApp.keyWindow?.performClose(nil)
                    } else {
                        doc.closeCurrentFile()
                    }
                }
                .keyboardShortcut("w")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { doc.undo() }
                    .keyboardShortcut("z")
                    .disabled(!doc.canUndo)
                Button("Redo") { doc.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!doc.canRedo)
            }
            CommandMenu("Measurement") {
                // ⌘⌫, not bare ⌫ — a menu key equivalent would steal the key from the
                // name and length fields. The canvas handles bare ⌫ when it has focus.
                Button("Delete") { doc.removeSelected() }
                    .keyboardShortcut(.delete, modifiers: [.command])
                    .disabled(doc.selectedSegmentID == nil)
                Button("Use as Reference") {
                    guard let id = doc.selectedSegmentID else { return }
                    doc.toggleReference(id)
                }
                .keyboardShortcut("r")
                .disabled(doc.selectedSegmentID == nil)
            }
            CommandGroup(after: .sidebar) {
                Button("Zoom In") { doc.stepZoom(1.25) }.keyboardShortcut("+")
                Button("Zoom Out") { doc.stepZoom(0.8) }.keyboardShortcut("-")
                Button("Actual Size") { doc.zoom = 1 }.keyboardShortcut("0")
                Button("Fit to Window") { doc.fitZoom() }.keyboardShortcut("9")
            }
        }
    }
}

struct ContentView: View {
    @Bindable var doc: Document
    @State private var importing = false
    @State private var inspecting = true

    var body: some View {
        NavigationSplitView {
            PageList(doc: doc)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            // The toolbar belongs to the detail column. On the split view itself,
            // SwiftUI spreads its items across the columns and the trailing button
            // lands over the sidebar.
            detail
                .frame(minWidth: 420)
                .toolbar { toolbar }
        }
        .inspector(isPresented: $inspecting) {
            MeasurementList(doc: doc)
                .inspectorColumnWidth(min: 250, ideal: 290, max: 380)
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.image, .pdf],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            doc.open(urls)
        }
        .dropDestination(for: URL.self) { urls, _ in
            doc.open(urls)
            return true
        }
        .alert("Save", isPresented: Binding(get: { doc.saveReport != nil },
                                            set: { if !$0 { doc.saveReport = nil } })) {
            Button("OK") { doc.saveReport = nil }
        } message: {
            Text(doc.saveReport ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .caliperExport)) { _ in exportNow() }
    }

    private func exportNow() {
        guard let page = doc.page else { return }
        let group = doc.pages.filter { $0.source == page.source }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Exporter.suggestedName(for: page)
        panel.allowedContentTypes = [Exporter.isPDF(page) ? .pdf : .png]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let labels = Dictionary(uniqueKeysWithValues: group.map { sheet in
            (sheet.id, sheet.segments.enumerated().map {
                doc.label(for: $1, number: $0 + 1, on: sheet)
            })
        })
        let captions = Dictionary(uniqueKeysWithValues: group.map { sheet in
            (sheet.id, sheet.segments.map { doc.caption(for: $0, on: sheet) })
        })
        do {
            try Exporter.export(pages: group, labels: labels, captions: captions,
                                tint: doc.lineColor, to: url)
            doc.saveReport = "Exported \(url.lastPathComponent)."
        } catch {
            doc.saveReport = error.localizedDescription
        }
    }

    @ViewBuilder private var detail: some View {
        if let page = doc.page {
            CanvasView(doc: doc, page: page)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "ruler").font(.system(size: 40)).foregroundStyle(.tertiary)
                Text("Drop images or PDFs here").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button("Open…", systemImage: "folder") { importing = true }
                .keyboardShortcut("o")
        }
        // HIG puts the inspector toggle at the trailing edge, above the inspector.
        ToolbarItem(placement: .primaryAction) {
            Button("Inspector", systemImage: "sidebar.trailing") { inspecting.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

struct PageList: View {
    @Bindable var doc: Document

    var body: some View {
        List(selection: $doc.selectedPageID) {
            ForEach(doc.pages) { page in
                HStack(spacing: 8) {
                    Image(nsImage: page.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .background(.white)
                        .border(.separator)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(page.name).lineLimit(2)
                        Text(summary(of: page)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(page.id)
            }
        }
        .onChange(of: doc.selectedPageID) { _, _ in
            doc.selectedSegmentID = nil
            doc.fitZoom()
        }
    }

    private func summary(of page: Page) -> String {
        let count = page.segments.count
        let scale = doc.scale(of: page) == nil ? "no reference" : "scaled"
        return "\(count) line\(count == 1 ? "" : "s") · \(scale)"
    }
}

struct MeasurementList: View {
    @Bindable var doc: Document

    var body: some View {
        Form {
            Section("Scale") {
                TextField("Unit", text: $doc.unit)
                ColorPicker("Measurement colour", selection: $doc.lineColor, supportsOpacity: false)
                Picker("Reference", selection: $doc.scaleSource) {
                    Text("This page").tag(nil as Page.ID?)
                    ForEach(doc.scaleLenders) { lender in
                        Text(lender.name).tag(lender.id as Page.ID?)
                    }
                }
                if doc.scaleSource != nil {
                    Text("Borrowed from another page.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if doc.page?.reference != nil {
                    TextField("Reference length", value: $doc.referenceLength, format: .number)
                } else {
                    Text("Draw a line over a known dimension, then mark it as the reference.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let readout = doc.scaleReadout {
                    Text(readout).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                if let warning = doc.referenceWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Measurements") {
                if doc.page?.segments.isEmpty ?? true {
                    Text("Drag on the image to measure.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array((doc.page?.segments ?? []).enumerated()), id: \.element.id) { index, segment in
                    row(index: index, segment: segment)
                }
            }

            Section {
                Text("""
                     ⇧ drag locks to 90°. Click a line, then drag a large dot or nudge it \
                     with the arrow keys — ⇧ for 10 px, ⌥ to move the whole line.
                     """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func row(index: Int, segment: Segment) -> some View {
        let isReference = segment.id == doc.page?.referenceID
        let isSelected = segment.id == doc.selectedSegmentID
        return HStack(spacing: 6) {
            Text("\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
            TextField("Name", text: Binding(get: { doc.name(of: segment.id) },
                                            set: { doc.setName($0, for: segment.id) }))
                .textFieldStyle(.plain)
                .onTapGesture { doc.selectedSegmentID = segment.id }
            Text(doc.measurement(for: segment))
                .monospacedDigit()
                .foregroundStyle(isReference ? .orange : .secondary)
            Button("Use as reference", systemImage: isReference ? "ruler.fill" : "ruler") {
                doc.toggleReference(segment.id)
            }
            .foregroundStyle(isReference ? .orange : .secondary)
            Button("Delete", systemImage: "trash") { doc.remove(segment.id) }
                .foregroundStyle(.secondary)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
    }
}

extension Notification.Name {
    /// SwiftUI commands cannot reach a view's NSSavePanel directly — this is the bridge.
    static let caliperExport = Notification.Name("caliper.export")
}
