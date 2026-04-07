import Foundation
import AppKit
import CoreText

enum DocumentExporterError: LocalizedError {
    case markdownParseFailed
    case pdfContextCreationFailed

    var errorDescription: String? {
        switch self {
        case .markdownParseFailed:
            return "Markdown could not be parsed for export."
        case .pdfContextCreationFailed:
            return "PDF context could not be created."
        }
    }
}

enum DocumentExporter {
    static func exportHTML(markdown: String, to url: URL) throws {
        let attributed = try makeAttributedMarkdown(markdown: markdown)
        let range = NSRange(location: 0, length: attributed.length)
        let data = try attributed.data(
            from: range,
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
        )
        try data.write(to: url, options: .atomic)
    }

    static func exportPDF(markdown: String, to url: URL) throws {
        let attributed = try makeAttributedMarkdown(markdown: markdown)
        let data = try makePDFData(from: attributed)
        try data.write(to: url, options: .atomic)
    }

    @available(macOS 13.0, *)
    static func exportDOCX(markdown: String, to url: URL) throws {
        let attributed = try makeAttributedMarkdown(markdown: markdown)
        let range = NSRange(location: 0, length: attributed.length)
        let data = try attributed.data(
            from: range,
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.officeOpenXML
            ]
        )
        try data.write(to: url, options: .atomic)
    }

    private static func makeAttributedMarkdown(markdown: String) throws -> NSAttributedString {
        let parsedMarkdown: AttributedString
        do {
            let options = AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
            parsedMarkdown = try AttributedString(markdown: markdown, options: options)
        } catch {
            throw DocumentExporterError.markdownParseFailed
        }

        let mutable = NSMutableAttributedString(attributedString: NSAttributedString(parsedMarkdown))
        let fullRange = NSRange(location: 0, length: mutable.length)
        if fullRange.length > 0 {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 6
            paragraphStyle.paragraphSpacing = 8
            paragraphStyle.lineBreakMode = .byWordWrapping
            mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

            mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
                if value == nil {
                    mutable.addAttribute(.font, value: NSFont.systemFont(ofSize: 13), range: range)
                }
            }
            mutable.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
                if value == nil {
                    mutable.addAttribute(.foregroundColor, value: NSColor.black, range: range)
                }
            }
        }

        return mutable
    }

    private static func makePDFData(from attributed: NSAttributedString) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let textRect = pageRect.insetBy(dx: 64, dy: 72)

        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else {
            throw DocumentExporterError.pdfContextCreationFailed
        }

        var mediaBox = pageRect
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw DocumentExporterError.pdfContextCreationFailed
        }

        if attributed.length == 0 {
            context.beginPDFPage(nil)
            context.endPDFPage()
            context.closePDF()
            return mutableData as Data
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        var currentRange = CFRange(location: 0, length: 0)

        while currentRange.location < attributed.length {
            context.beginPDFPage(nil)
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: 0, y: pageRect.height)
            context.scaleBy(x: 1, y: -1)

            let path = CGMutablePath()
            path.addRect(textRect)
            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
            CTFrameDraw(frame, context)

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            context.restoreGState()
            context.endPDFPage()

            guard visibleRange.length > 0 else { break }
            currentRange.location += visibleRange.length
        }

        context.closePDF()
        return mutableData as Data
    }
}
