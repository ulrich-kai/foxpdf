import Foundation
import Combine
import CoreGraphics
import PDFKit
import ImageIO

// MARK: - Compression Quality Preset

enum CompressionPreset: String, CaseIterable, Identifiable {
    case screen   = "Screen (72 dpi)"
    case ebook    = "eBook (150 dpi)"
    case printer  = "Print (300 dpi)"
    case prepress = "High Quality (600 dpi)"
    case custom   = "Custom"

    var id: String { rawValue }

    var imageQuality: Double {
        switch self {
        case .screen:   return 0.25
        case .ebook:    return 0.50
        case .printer:  return 0.75
        case .prepress: return 0.92
        case .custom:   return 0.60
        }
    }

    var maxDPI: Double {
        switch self {
        case .screen:   return 72
        case .ebook:    return 150
        case .printer:  return 300
        case .prepress: return 600
        case .custom:   return 150
        }
    }

    var description: String {
        switch self {
        case .screen:   return "Bildschirm, E-Mail"
        case .ebook:    return "Tablet, eBook"
        case .printer:  return "Bürodruck"
        case .prepress: return "Druckvorstufe"
        case .custom:   return "Eigene Einstellungen"
        }
    }
}

// MARK: - Compression Result

struct CompressionResult: Identifiable {
    let id = UUID()
    let inputURL: URL
    let outputURL: URL
    let originalSize: Int64
    let compressedSize: Int64

    var savings: Double {
        guard originalSize > 0 else { return 0 }
        return Double(originalSize - compressedSize) / Double(originalSize) * 100
    }

    var originalSizeFormatted: String   { formatBytes(originalSize) }
    var compressedSizeFormatted: String { formatBytes(compressedSize) }

    private func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

// MARK: - PDF Compressor (ViewModel)

@MainActor
class PDFCompressor: ObservableObject {

    @Published var progress: Double = 0
    @Published var statusMessage: String = ""
    @Published var isProcessing: Bool = false
    @Published var results: [CompressionResult] = []
    @Published var errors: [String] = []

    private var isCancelled = false

    func compress(
        urls: [URL],
        preset: CompressionPreset,
        customQuality: Double,
        customDPI: Double,
        outputDirectory: URL?,
        stripMetadata: Bool,
        downscaleImages: Bool
    ) async {
        isProcessing = true
        isCancelled  = false
        results      = []
        errors       = []
        progress     = 0

        let quality = preset == .custom ? customQuality : preset.imageQuality
        let maxDPI  = preset == .custom ? customDPI     : preset.maxDPI

        for (index, url) in urls.enumerated() {
            guard !isCancelled else { break }

            statusMessage = "Verarbeite: \(url.lastPathComponent)"

            do {
                let result = try await Task(priority: .userInitiated) {
                    try FoxPDFEngine.compress(
                        url: url,
                        quality: quality,
                        maxDPI: maxDPI,
                        outputDirectory: outputDirectory,
                        stripMetadata: stripMetadata,
                        downscaleImages: downscaleImages
                    )
                }.value
                results.append(result)
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }

            progress = Double(index + 1) / Double(urls.count)
        }

        isProcessing  = false
        statusMessage = isCancelled ? "Abgebrochen." : "Fertig!"
    }

    func cancel() { isCancelled = true }
}

// MARK: - FoxPDFEngine

enum FoxPDFEngine {

    nonisolated static func compress(
        url: URL,
        quality: Double,
        maxDPI: Double,
        outputDirectory: URL?,
        stripMetadata: Bool,
        downscaleImages: Bool
    ) throws -> CompressionResult {

        // ── iOS/iPadOS: Die vom fileImporter gelieferten URLs sind
        //    Security-Scoped. Ohne diesen Aufruf verweigert das System
        //    den Lesezugriff → "PDF konnte nicht geöffnet werden".
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let pdfDoc = PDFDocument(url: url) else {
            throw FoxPDFError.cannotOpenFile
        }

        let originalSize = fileSize(at: url)

        // ── Ausgabepfad bestimmen.
        //    iOS-Sandbox: Schreibzugriff nur in app-eigene Verzeichnisse.
        //    Wir schreiben in das temporäre Verzeichnis der App;
        //    von dort kann der User die Datei via ShareSheet exportieren.
        let resolvedOutDir: URL = {
            if let dir = outputDirectory { return dir }
            #if os(iOS)
            return FileManager.default.temporaryDirectory
            #else
            return url.deletingLastPathComponent()
            #endif
        }()

        let outURL = buildOutputURL(for: url, in: resolvedOutDir)

        // ── PDF rendern und komprimieren
        let cfData = CFDataCreateMutable(kCFAllocatorDefault, 0)!
        try renderPDF(
            pdfDoc: pdfDoc,
            into: cfData,
            quality: quality,
            maxDPI: maxDPI,
            downscaleImages: downscaleImages
        )

        let pdfData = cfData as Data
        try pdfData.write(to: outURL, options: .atomic)

        if stripMetadata { stripMetadataAtURL(outURL) }

        return CompressionResult(
            inputURL: url,
            outputURL: outURL,
            originalSize: originalSize,
            compressedSize: fileSize(at: outURL)
        )
    }

    // MARK: - Render loop

    private static func renderPDF(
        pdfDoc: PDFDocument,
        into cfData: CFMutableData,
        quality: Double,
        maxDPI: Double,
        downscaleImages: Bool
    ) throws {
        guard let consumer = CGDataConsumer(data: cfData),
              let ctx = CGContext(consumer: consumer, mediaBox: nil, nil)
        else { throw FoxPDFError.cannotCreateContext }

        for i in 0..<pdfDoc.pageCount {
            guard let page = pdfDoc.page(at: i) else { continue }

            var mediaBox = page.bounds(for: .mediaBox)

            // Übergabe der MediaBox als rohe CFData – kein NSValue nötig
            let boxData = withUnsafeBytes(of: &mediaBox) { Data($0) } as CFData
            let pageInfo = [kCGPDFContextMediaBox as String: boxData] as CFDictionary

            ctx.beginPDFPage(pageInfo)
            ctx.translateBy(x: 0, y: mediaBox.height)
            ctx.scaleBy(x: 1, y: -1)

            if downscaleImages {
                renderDownscaled(page: page, in: ctx, box: mediaBox, quality: quality, dpi: maxDPI)
            } else {
                page.draw(with: .mediaBox, to: ctx)
            }

            ctx.endPDFPage()
        }

        ctx.closePDF()
    }

    // MARK: - Downscale + JPEG-Rekomprimierung

    private static func renderDownscaled(
        page: PDFPage,
        in ctx: CGContext,
        box: CGRect,
        quality: Double,
        dpi: Double
    ) {
        let scale  = dpi / 72.0
        let width  = max(1, Int(box.width  * CGFloat(scale)))
        let height = max(1, Int(box.height * CGFloat(scale)))

        guard let bmp = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { page.draw(with: .mediaBox, to: ctx); return }

        bmp.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        bmp.fill(CGRect(x: 0, y: 0, width: width, height: height))
        bmp.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        page.draw(with: .mediaBox, to: bmp)

        guard let rendered = bmp.makeImage() else {
            page.draw(with: .mediaBox, to: ctx); return
        }

        let final = recompressJPEG(rendered, quality: quality) ?? rendered
        ctx.draw(final, in: box)
    }

    private static func recompressJPEG(_ image: CGImage, quality: Double) -> CGImage? {
        let data = CFDataCreateMutable(kCFAllocatorDefault, 0)!
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        guard let src = CGImageSourceCreateWithData(data, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    // MARK: - Metadaten entfernen

    private static func stripMetadataAtURL(_ url: URL) {
        guard let doc = PDFDocument(url: url) else { return }
        var attrs = doc.documentAttributes ?? [:]
        [PDFDocumentAttribute.authorAttribute,
         PDFDocumentAttribute.creatorAttribute,
         PDFDocumentAttribute.producerAttribute,
         PDFDocumentAttribute.creationDateAttribute,
         PDFDocumentAttribute.modificationDateAttribute,
         PDFDocumentAttribute.subjectAttribute,
         PDFDocumentAttribute.keywordsAttribute
        ].forEach { attrs.removeValue(forKey: $0) }
        doc.documentAttributes = attrs
        doc.write(to: url)
    }

    // MARK: - Hilfsfunktionen

    static func buildOutputURL(for url: URL, in directory: URL) -> URL {
        let stem = url.deletingPathExtension().lastPathComponent
        return directory
            .appendingPathComponent("\(stem)_compressed")
            .appendingPathExtension("pdf")
    }

    static func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}

// MARK: - Fehler

enum FoxPDFError: LocalizedError {
    case cannotOpenFile
    case cannotCreateContext

    var errorDescription: String? {
        switch self {
        case .cannotOpenFile:
            return "PDF konnte nicht geöffnet werden. Bitte prüfe die Dateiberechtigung."
        case .cannotCreateContext:
            return "Rendering-Kontext konnte nicht erstellt werden."
        }
    }
}
