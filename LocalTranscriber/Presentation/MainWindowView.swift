import SwiftUI

struct MainWindowView: View {
    @StateObject private var viewModel = MainWindowViewModel()
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 16) {
            toolbar
            FileDropView(
                supportedExtensions: settings.supportedExtensions,
                selectedFile: viewModel.selectedFile,
                onFileSelected: viewModel.selectFile(url:preferredFileName:)
            )
            TranscriptEditorView(
                text: $viewModel.transcriptText,
                isEditable: viewModel.uiState == .done || viewModel.currentTranscript != nil,
                onCopy: viewModel.copyTranscript
            )
            StatusBarView(
                uiState: viewModel.uiState,
                progress: viewModel.progressDisplay,
                canCancel: viewModel.canCancel,
                onCancel: viewModel.cancelTranscription
            )
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 560)
        .onAppear {
            viewModel.refreshModelAvailability()
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("モデル", selection: $settings.selectedModelID) {
                ForEach(settings.models) { model in
                    Label {
                        Text(model.displayName)
                    } icon: {
                        Image(systemName: modelIcon(for: model))
                    }
                    .tag(model.id)
                }
            }
            .frame(width: 240)
            .disabled(viewModel.isBusy)

            if viewModel.canDownloadSelectedModel {
                Button {
                    viewModel.downloadSelectedModel()
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .disabled(viewModel.isBusy)
                .help("選択中のモデルをダウンロード")
            }

            Picker("言語", selection: $settings.selectedLanguageID) {
                ForEach(settings.languages) { language in
                    Text(language.displayName).tag(language.id)
                }
            }
            .frame(width: 140)
            .disabled(viewModel.isBusy)

            Spacer()

            Button("Start") {
                viewModel.startTranscription()
            }
            .disabled(!viewModel.canStartTranscription)
            .keyboardShortcut(.return, modifiers: [.command])

            Menu("Export") {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.displayName) {
                        viewModel.exportTranscript(format: format)
                    }
                }
            }
            .disabled(!viewModel.canExport)
        }
    }

    private func modelIcon(for model: ModelOption) -> String {
        viewModel.isModelDownloaded(model) ? "checkmark.circle" : "arrow.down.circle"
    }
}
