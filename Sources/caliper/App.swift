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
    }
}

struct ContentView: View {
    @Bindable var doc: Document
    @State private var importing = false

    var body: some View {
        NavigationSplitView {
            Sidebar(doc: doc)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            CanvasView(doc: doc)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Tool", selection: $doc.tool) {
                    ForEach(Tool.allCases) { tool in
                        Label(tool.rawValue, systemImage: tool.symbol).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(doc.image == nil)
            }
            ToolbarItem {
                Button("Open Image…", systemImage: "folder") { importing = true }
                    .keyboardShortcut("o")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            doc.open(url)
        }
    }
}

struct Sidebar: View {
    @Bindable var doc: Document

    var body: some View {
        Form {
            Section("Reference") {
                TextField("Known length", value: $doc.knownLength, format: .number)
                TextField("Unit", text: $doc.unit)
                Text(doc.isCalibrated
                     ? "Drag in Calibrate mode to move the reference."
                     : "Drag across a known dimension in Calibrate mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Measurements") {
                if doc.segments.isEmpty {
                    Text("None yet").foregroundStyle(.secondary)
                }
                ForEach(Array(doc.segments.enumerated()), id: \.element.id) { index, segment in
                    HStack {
                        Text("\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
                        Text(doc.label(for: segment)).monospacedDigit()
                        Spacer()
                        Button("Delete", systemImage: "trash") { doc.remove(segment) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
            }

            Section {
                Text("Hold ⇧ while dragging to lock the line to 90°.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
