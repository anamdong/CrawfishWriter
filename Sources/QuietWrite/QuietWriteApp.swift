import SwiftUI
import AppKit

@main
struct CrawfishWriterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            WriterCommands()
        }
    }
}

private struct WriterCommands: Commands {
    @FocusedValue(\.activeAppState) private var appState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Empty Document") {
                appState?.newDocument()
            }
            .keyboardShortcut("N", modifiers: [.command, .shift])
            .disabled(appState == nil)

            Button("Open…") {
                appState?.openDocument()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(appState == nil)

            Divider()

            Button("Close Window") {
                NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                appState?.saveDocument()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(appState == nil)

            Button("Save As…") {
                appState?.saveDocumentAs()
            }
            .keyboardShortcut("S", modifiers: [.command, .shift])
            .disabled(appState == nil)
        }

        CommandGroup(after: .saveItem) {
            Divider()

            Button("Export as PDF…") {
                appState?.exportPDF()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(appState == nil)

            Button("Export as HTML…") {
                appState?.exportHTML()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(appState == nil)

            if appState?.canExportDOCX == true {
                Button("Export as DOCX…") {
                    appState?.exportDOCX()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(appState == nil)
            }
        }

        CommandMenu("View") {
            Button(appState?.isPreviewPanelVisible == true ? "Hide Markdown Preview" : "Show Markdown Preview") {
                appState?.togglePreviewPanel()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(appState == nil)

            Divider()

            Button("Cycle Focus Mode") {
                appState?.cycleFocusMode()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(appState == nil)

            Button("Focus Current Sentence") {
                appState?.focusMode = .sentence
            }
            .keyboardShortcut("1", modifiers: [.command, .control])
            .disabled(appState == nil)

            Button("Focus Current Paragraph") {
                appState?.focusMode = .paragraph
            }
            .keyboardShortcut("2", modifiers: [.command, .control])
            .disabled(appState == nil)

            Button("Focus Off") {
                appState?.focusMode = .off
            }
            .keyboardShortcut("0", modifiers: [.command, .control])
            .disabled(appState == nil)
        }
    }
}
