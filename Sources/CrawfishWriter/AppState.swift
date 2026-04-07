import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var text: String = ""
    @Published var isPreviewPanelVisible: Bool = false
    @Published var focusMode: FocusMode = .off
    @Published var editorFontSize: CGFloat = 17
    @Published var useDarkMode: Bool = false
    @Published var documentURL: URL? {
        didSet { refreshWindowDocumentMetadata() }
    }
    @Published var isDirty: Bool = false {
        didSet { refreshWindowDocumentMetadata() }
    }
    @Published var errorMessage: String?

    private weak var configuredWindow: NSWindow?
    let minimumEditorFontSize: CGFloat = 12
    let maximumEditorFontSize: CGFloat = 30
    private let defaultDocumentTitle = "Untitled.md"

    var canExportDOCX: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    func userEdited(text newValue: String) {
        guard text != newValue else { return }
        text = newValue
        isDirty = true
    }

    func togglePreviewPanel() {
        isPreviewPanelVisible.toggle()
    }

    func showPreviewPanel() {
        isPreviewPanelVisible = true
    }

    func hidePreviewPanel() {
        isPreviewPanelVisible = false
    }

    func cycleFocusMode() {
        focusMode = focusMode.next()
    }

    func increaseEditorFontSize() {
        setEditorFontSize(editorFontSize + 1)
    }

    func decreaseEditorFontSize() {
        setEditorFontSize(editorFontSize - 1)
    }

    func setEditorFontSize(_ newValue: CGFloat) {
        editorFontSize = min(max(newValue, minimumEditorFontSize), maximumEditorFontSize)
    }

    func toggleDarkMode() {
        useDarkMode.toggle()
        if let configuredWindow {
            applyAppearance(to: configuredWindow)
        }
    }

    var characterCount: Int {
        text.count
    }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    func configure(window: NSWindow?) {
        guard let window else { return }

        if configuredWindow !== window {
            configuredWindow = window

            window.styleMask.insert(.titled)
            window.styleMask.insert(.closable)
            window.styleMask.insert(.miniaturizable)
            window.styleMask.insert(.resizable)
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = true
            window.toolbar = nil
            window.tabbingMode = .disallowed
            window.isMovableByWindowBackground = true
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenAllowsTiling)
            window.backgroundColor = .textBackgroundColor
            if #available(macOS 11.0, *) {
                window.titlebarSeparatorStyle = .none
            }

            let buttons: [NSWindow.ButtonType] = [
                .closeButton,
                .miniaturizeButton,
                .zoomButton
            ]
            for button in buttons {
                guard let control = window.standardWindowButton(button) else { continue }
                control.isHidden = false
                control.isEnabled = true
                control.alphaValue = 1
            }
        }

        applyAppearance(to: window)
        refreshWindowDocumentMetadata()
    }

    private func applyAppearance(to window: NSWindow) {
        window.appearance = NSAppearance(named: useDarkMode ? .darkAqua : .aqua)
        window.backgroundColor = .windowBackgroundColor
    }

    private func refreshWindowDocumentMetadata() {
        guard let window = configuredWindow else { return }

        window.title = documentURL?.lastPathComponent ?? defaultDocumentTitle
        window.representedURL = documentURL
        window.isDocumentEdited = isDirty

        if let documentIconButton = window.standardWindowButton(.documentIconButton) {
            documentIconButton.isHidden = documentURL == nil
            documentIconButton.isEnabled = documentURL != nil
        }
    }

    func newDocument() {
        guard confirmDiscardIfNeeded() else { return }
        text = ""
        documentURL = nil
        isDirty = false
    }

    func openDocument() {
        guard confirmDiscardIfNeeded() else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = openableContentTypes()
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            text = try Self.readText(from: url)
            documentURL = url
            isDirty = false
        } catch {
            present(error: error)
        }
    }

    func saveDocument() {
        if let documentURL {
            writeDocument(to: documentURL)
        } else {
            saveDocumentAs()
        }
    }

    func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = savableContentTypes()
        panel.nameFieldStringValue = suggestedSaveName()
        panel.prompt = "Save"

        if let currentURL = documentURL {
            panel.directoryURL = currentURL.deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeDocument(to: url)
    }

    func exportPDF() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = exportName(fileExtension: "pdf")
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try DocumentExporter.exportPDF(markdown: text, to: url)
        } catch {
            present(error: error)
        }
    }

    func exportHTML() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = exportName(fileExtension: "html")
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try DocumentExporter.exportHTML(markdown: text, to: url)
        } catch {
            present(error: error)
        }
    }

    func exportDOCX() {
        guard #available(macOS 13.0, *) else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        if let docxType = UTType(filenameExtension: "docx") {
            panel.allowedContentTypes = [docxType]
        }
        panel.nameFieldStringValue = exportName(fileExtension: "docx")
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try DocumentExporter.exportDOCX(markdown: text, to: url)
        } catch {
            present(error: error)
        }
    }

    private func writeDocument(to url: URL) {
        do {
            guard let data = text.data(using: .utf8) else {
                throw AppStateError.utf8EncodingFailed
            }
            try data.write(to: url, options: .atomic)
            documentURL = url
            isDirty = false
        } catch {
            present(error: error)
        }
    }

    private func suggestedSaveName() -> String {
        if let documentURL {
            return documentURL.lastPathComponent
        }
        return "Untitled.md"
    }

    private func exportName(fileExtension: String) -> String {
        let base = documentURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        return "\(base).\(fileExtension)"
    }

    private func present(error: Error) {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            errorMessage = description
            return
        }
        errorMessage = error.localizedDescription
    }

    private func confirmDiscardIfNeeded() -> Bool {
        guard isDirty else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard unsaved changes?"
        alert.informativeText = "The current document has unsaved edits."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func readText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let value = String(data: data, encoding: .utf8) {
            return value
        }
        if let value = String(data: data, encoding: .utf16) {
            return value
        }
        if let value = String(data: data, encoding: .unicode) {
            return value
        }
        throw AppStateError.unreadableTextEncoding
    }

    private func openableContentTypes() -> [UTType] {
        var types: [UTType] = [.plainText, .text]
        if let md = UTType(filenameExtension: "md") {
            types.append(md)
        }
        if let markdown = UTType(filenameExtension: "markdown") {
            types.append(markdown)
        }
        return types
    }

    private func savableContentTypes() -> [UTType] {
        var types: [UTType] = []
        if let md = UTType(filenameExtension: "md") {
            types.append(md)
        }
        types.append(.plainText)
        return types
    }
}

enum AppStateError: LocalizedError {
    case utf8EncodingFailed
    case unreadableTextEncoding

    var errorDescription: String? {
        switch self {
        case .utf8EncodingFailed:
            return "The document could not be encoded as UTF-8."
        case .unreadableTextEncoding:
            return "The selected file is not a supported plain-text encoding."
        }
    }
}
