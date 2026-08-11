import CoreGraphics
import Foundation
import ImageIO
import PDFKit

enum MetadataError: LocalizedError {
    case unreadable(String)
    case unwritable(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "Could not read \(name)."
        case .unwritable(let name): return "Could not write \(name)."
        }
    }
}

/// Measurements travel in the file itself: XMP for images, and — because PDFKit
/// exposes no XMP writer and drops unknown Info keys — a hidden note annotation
/// for PDFs, which is the only PDF carrier that survives without overwriting a
/// user-visible field.
enum Metadata {
    private static let namespace = "https://caliper.gustaf.dev/ns/1.0/"
    private static let prefix = "caliper"
    private static let property = "caliper:document"
    private static let pdfMarker = "caliper/1 "

    static func read(from url: URL) -> Stored? {
        let json = isPDF(url) ? readPDF(url) : readImage(url)
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    static func write(_ stored: Stored, to url: URL) throws {
        let json = String(decoding: try JSONEncoder().encode(stored), as: UTF8.self)
        if isPDF(url) {
            try writePDF(json, to: url)
        } else {
            try writeImage(json, to: url)
        }
    }

    private static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    private static func readImage(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let tag = CGImageMetadataCopyTagWithPath(metadata, nil, property as CFString)
        else { return nil }
        return CGImageMetadataTagCopyValue(tag) as? String
    }

    private static func writeImage(_ json: String, to url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw MetadataError.unreadable(url.lastPathComponent) }

        let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
            .flatMap(CGImageMetadataCreateMutableCopy) ?? CGImageMetadataCreateMutable()
        guard CGImageMetadataRegisterNamespaceForPrefix(
                metadata, namespace as CFString, prefix as CFString, nil),
              CGImageMetadataSetValueWithPath(metadata, nil, property as CFString, json as CFString)
        else { throw MetadataError.unwritable(url.lastPathComponent) }

        // Encode beside the original and swap, so a failure never truncates the source.
        let staging = url.deletingLastPathComponent()
            .appendingPathComponent(".caliper-\(UUID().uuidString)")
        guard let destination = CGImageDestinationCreateWithURL(staging as CFURL, type, 1, nil)
        else { throw MetadataError.unwritable(url.lastPathComponent) }
        CGImageDestinationAddImageAndMetadata(
            destination, image, metadata,
            [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: staging)
            throw MetadataError.unwritable(url.lastPathComponent)
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: staging)
    }

    private static func readPDF(_ url: URL) -> String? {
        guard let pdf = PDFDocument(url: url) else { return nil }
        return notes(in: pdf).first.map { String($0.contents!.dropFirst(pdfMarker.count)) }
    }

    private static func notes(in pdf: PDFDocument) -> [PDFAnnotation] {
        (0..<pdf.pageCount).compactMap(pdf.page).flatMap(\.annotations)
            .filter { $0.contents?.hasPrefix(pdfMarker) ?? false }
    }

    private static func writePDF(_ json: String, to url: URL) throws {
        guard let pdf = PDFDocument(url: url), let first = pdf.page(at: 0) else {
            throw MetadataError.unreadable(url.lastPathComponent)
        }
        for stale in notes(in: pdf) { stale.page?.removeAnnotation(stale) }

        let note = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 forType: .text, withProperties: nil)
        note.contents = pdfMarker + json
        note.shouldDisplay = false
        note.shouldPrint = false
        first.addAnnotation(note)

        let staging = url.deletingLastPathComponent()
            .appendingPathComponent(".caliper-\(UUID().uuidString).pdf")
        guard pdf.write(to: staging) else {
            throw MetadataError.unwritable(url.lastPathComponent)
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: staging)
    }
}
