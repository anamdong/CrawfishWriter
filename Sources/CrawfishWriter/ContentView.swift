import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var isPreviewButtonHovered = false

    private var previewButtonTrailingPadding: CGFloat {
        appState.isPreviewPanelVisible ? 42 : 26
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ZStack {
                        Color(nsColor: .textBackgroundColor)
                            .ignoresSafeArea()

                        WriterEditorView(
                            text: $appState.text,
                            focusMode: appState.focusMode
                        ) { editedText in
                            appState.userEdited(text: editedText)
                        }
                    }

                    if appState.isPreviewPanelVisible {
                        Divider()
                            .opacity(0.5)
                        MarkdownWebPreviewView(markdown: appState.text)
                            .frame(minWidth: 340, idealWidth: 460, maxWidth: 760, maxHeight: .infinity)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }

                HStack {
                    Text("Crawfish Writer")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(appState.wordCount) words  ·  \(appState.characterCount) characters")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Rectangle()
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                )
                .overlay(alignment: .top) {
                    Divider().opacity(0.45)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: appState.isPreviewPanelVisible)

            Button(action: { appState.togglePreviewPanel() }) {
                Text(appState.isPreviewPanelVisible ? "Hide Preview" : "Preview")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(
                                isPreviewButtonHovered
                                ? Color.black.opacity(0.14)
                                : Color.black.opacity(0.08)
                            )
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                Color.black.opacity(isPreviewButtonHovered ? 0.30 : 0.16),
                                lineWidth: 1
                            )
                    )
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isPreviewButtonHovered = isHovered
                }
            }
            .padding(.top, 10)
            .padding(.trailing, previewButtonTrailingPadding)
            .zIndex(5)
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 1)
        }
        .background(
            WindowAccessor { window in
                appState.configure(window: window)
            }
        )
        .focusedSceneValue(\.activeAppState, appState)
        .alert(
            "Operation Failed",
            isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        appState.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }
}
