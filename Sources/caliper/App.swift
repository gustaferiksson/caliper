import SwiftUI
import UniformTypeIdentifiers

@main
struct CaliperApp: App {
    @State private var doc = Document()

    var body: some Scene {
        WindowGroup("Caliper") {
            ContentView(doc: doc)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save Measurements") { doc.saveNow() }
                    .keyboardShortcut("s")
                    .disabled(doc.pages.isEmpty)
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
                Button("Delete") { doc.removeSelected() }
                    .keyboardShortcut(.delete, modifiers: [])
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
                Button("Zoom to Fit") { doc.fitZoom() }.keyboardShortcut("0")
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
            detail
        }
        .toolbar { toolbar }
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
                Text("⇧ drag locks to 90°. Drag an endpoint to adjust. ⌘Z undoes.")
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
            Text(doc.measurement(for: segment))
                .monospacedDigit()
                .foregroundStyle(isReference ? .orange : .primary)
            Spacer()
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
        .contentShape(Rectangle())
        .onTapGesture { doc.selectedSegmentID = segment.id }
    }
}
