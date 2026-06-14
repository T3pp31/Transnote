import SwiftUI

@MainActor
final class MainWindowViewModel: ObservableObject {
    @Published var uiState: TranscriptionUIState = .idle
    @Published var progressDisplay: TranscriptionProgressDisplay = .idle()
    @Published var selectedFile: AudioFileInfo?
    @Published var transcriptText: String = ""
    @Published var currentTranscript: Transcript?
    @Published var errorMessage: String?
    @Published var downloadedModelIDs: Set<String> = []
    @Published var isDownloadingModel = false

    private var activeJobID: UUID?
    private var transcriptionTask: Task<Void, Never>?
    private var modelDownloadTask: Task<Void, Never>?
    private var lastAnnouncedPhase: TranscriptionProgressPhase?

    private let transcriber: Transcriber
    private let audioFileService: AudioFileService
    private let audioImportService: AudioImportService
    private let exportService: ExportService
    private let fileAccess: SecurityScopedFileAccess
    private let settings: AppSettings
    private let modelAvailability: ModelAvailabilityService
    private let modelDownloadService: ModelDownloadService

    init(
        transcriber: Transcriber = WhisperKitTranscriber(),
        audioFileService: AudioFileService = AudioFileService(),
        audioImportService: AudioImportService = AudioImportService(),
        exportService: ExportService = ExportService(),
        fileAccess: SecurityScopedFileAccess = .shared,
        settings: AppSettings = .shared,
        modelAvailability: ModelAvailabilityService = ModelAvailabilityService(),
        modelDownloadService: ModelDownloadService = ModelDownloadService()
    ) {
        self.transcriber = transcriber
        self.audioFileService = audioFileService
        self.audioImportService = audioImportService
        self.exportService = exportService
        self.fileAccess = fileAccess
        self.settings = settings
        self.modelAvailability = modelAvailability
        self.modelDownloadService = modelDownloadService
        refreshModelAvailability()
    }

    var isBusy: Bool {
        uiState == .preparing || uiState == .transcribing || isDownloadingModel
    }

    var canStartTranscription: Bool {
        guard selectedFile != nil,
              !isBusy,
              let model = settings.selectedModel else {
            return false
        }
        return isModelDownloaded(model)
    }

    var canDownloadSelectedModel: Bool {
        guard !isBusy,
              let model = settings.selectedModel else {
            return false
        }
        return !isModelDownloaded(model)
    }

    var canCancel: Bool {
        isBusy
    }

    var canExport: Bool {
        currentTranscript != nil && !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refreshModelAvailability() {
        downloadedModelIDs = Set(
            settings.models
                .filter { modelAvailability.isDownloaded(whisperKitModelName: $0.whisperKitModelName) }
                .map(\.id)
        )
    }

    func isModelDownloaded(_ model: ModelOption) -> Bool {
        downloadedModelIDs.contains(model.id)
    }

    func downloadSelectedModel() {
        guard let model = settings.selectedModel,
              canDownloadSelectedModel else {
            return
        }

        errorMessage = nil
        isDownloadingModel = true
        uiState = .preparing
        progressDisplay = TranscriptionProgressDisplay.from(
            update: .make(phase: .downloadingModel, fraction: 0, modelDisplayName: model.displayName)
        )
        lastAnnouncedPhase = nil

        modelDownloadTask = Task {
            do {
                _ = try await modelDownloadService.downloadIfNeeded(
                    whisperKitModelName: model.whisperKitModelName,
                    modelDisplayName: model.displayName
                ) { update in
                    Task { @MainActor in
                        self.applyModelDownloadProgress(update)
                    }
                }

                refreshModelAvailability()
                uiState = .idle
                progressDisplay = .idle()
                announcePhaseIfNeeded(.finished)
                AppLogger.info("Model download completed: \(model.displayName)", logger: AppLogger.transcription)
            } catch {
                if Task.isCancelled {
                    uiState = .idle
                    progressDisplay = .idle()
                } else {
                    handleError(error)
                }
            }

            isDownloadingModel = false
            modelDownloadTask = nil
        }
    }

    func selectFile(url: URL) {
        errorMessage = nil

        // #region agent log
        DebugSessionLogger.log(
            location: "MainWindowViewModel.swift:selectFile",
            message: "selectFile called",
            data: [
                "url": url.path,
                "lastPathComponent": url.lastPathComponent,
                "pathExtension": url.pathExtension,
                "fileExists": String(FileManager.default.fileExists(atPath: url.path)),
            ],
            hypothesisId: "A,C"
        )
        // #endregion

        do {
            let importedURL = try audioImportService.importFile(from: url)
            // #region agent log
            DebugSessionLogger.log(
                location: "MainWindowViewModel.swift:selectFile",
                message: "import succeeded",
                data: [
                    "importedURL": importedURL.path,
                    "importedExtension": importedURL.pathExtension,
                ],
                hypothesisId: "B,E"
            )
            // #endregion
            let info = try audioFileService.validate(url: importedURL)
            // #region agent log
            DebugSessionLogger.log(
                location: "MainWindowViewModel.swift:selectFile",
                message: "validate succeeded",
                data: [
                    "fileName": info.fileName,
                    "fileExtension": info.fileExtension,
                    "fileSizeBytes": String(info.fileSizeBytes),
                ],
                hypothesisId: "A"
            )
            // #endregion
            selectedFile = info
            uiState = .idle
            progressDisplay = .idle()
        } catch {
            // #region agent log
            DebugSessionLogger.log(
                location: "MainWindowViewModel.swift:selectFile",
                message: "selectFile failed",
                data: [
                    "errorType": String(describing: type(of: error)),
                    "errorDescription": error.localizedDescription,
                ],
                hypothesisId: "A,B,C"
            )
            // #endregion
            handleError(error)
        }
    }

    func startTranscription() {
        guard let file = selectedFile,
              let model = settings.selectedModel else {
            let message = AppError.invalidConfiguration.errorDescription ?? "Invalid configuration"
            errorMessage = message
            uiState = .error(message)
            return
        }

        guard isModelDownloaded(model) else {
            let message = AppError.modelNotDownloaded(model.displayName).errorDescription ?? "Model not downloaded"
            errorMessage = message
            uiState = .error(message)
            return
        }

        settings.persist()
        errorMessage = nil
        uiState = .preparing
        progressDisplay = TranscriptionProgressDisplay.from(
            update: .make(phase: .initializing, fraction: 0, modelDisplayName: model.displayName)
        )
        lastAnnouncedPhase = nil

        let job = TranscriptionJob(
            audioFileURL: file.url,
            sourceFileName: file.fileName,
            modelID: model.id,
            whisperKitModelName: model.whisperKitModelName,
            modelDisplayName: model.displayName,
            languageID: settings.selectedLanguageID
        )

        activeJobID = job.id

        transcriptionTask = Task {
            do {
                let transcript = try await transcriber.transcribe(job) { update in
                    Task { @MainActor in
                        self.applyProgressUpdate(update)
                    }
                }

                currentTranscript = transcript
                transcriptText = transcript.fullText
                uiState = .done
                progressDisplay = .done()
                refreshModelAvailability()
                announcePhaseIfNeeded(.finished)
                AppLogger.info("Transcription completed for \(file.fileName)", logger: AppLogger.transcription)
            } catch {
                if Task.isCancelled {
                    uiState = .idle
                    progressDisplay = .idle()
                } else {
                    handleError(error)
                }
            }

            activeJobID = nil
            transcriptionTask = nil
        }
    }

    func cancelTranscription() {
        if let jobID = activeJobID {
            transcriber.cancel(jobID: jobID)
        }
        transcriptionTask?.cancel()
        transcriptionTask = nil
        activeJobID = nil

        modelDownloadTask?.cancel()
        modelDownloadTask = nil
        isDownloadingModel = false

        uiState = .idle
        progressDisplay = .idle()
        lastAnnouncedPhase = nil
    }

    func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptText, forType: .string)
    }

    func exportTranscript(format: ExportFormat) {
        guard var transcript = currentTranscript else { return }
        transcript.fullText = transcriptText

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultExportFilename(for: transcript, format: format)
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try exportService.write(transcript: transcript, format: format, to: url)
            AppLogger.info("Exported \(format.displayName) to \(url.path)", logger: AppLogger.export)
        } catch {
            handleError(error)
        }
    }

    private func applyModelDownloadProgress(_ update: TranscriptionProgressUpdate) {
        progressDisplay = TranscriptionProgressDisplay.from(update: update)
        uiState = .preparing
        announcePhaseIfNeeded(update.phase)
    }

    private func applyProgressUpdate(_ update: TranscriptionProgressUpdate) {
        progressDisplay = TranscriptionProgressDisplay.from(update: update)

        switch update.phase {
        case .transcribing, .convertingAudio:
            uiState = .transcribing
        case .loadingModel, .initializing:
            uiState = .preparing
        case .finished:
            break
        case .downloadingModel:
            break
        }

        announcePhaseIfNeeded(update.phase)
    }

    private func announcePhaseIfNeeded(_ phase: TranscriptionProgressPhase) {
        let majorPhases: Set<TranscriptionProgressPhase> = [
            .downloadingModel, .loadingModel, .transcribing, .finished
        ]
        guard majorPhases.contains(phase), lastAnnouncedPhase != phase else { return }
        lastAnnouncedPhase = phase
        AccessibilityNotification.Announcement(phase.rawValue).post()
    }

    private func defaultExportFilename(for transcript: Transcript, format: ExportFormat) -> String {
        let stem = URL(fileURLWithPath: transcript.sourceFileName).deletingPathExtension().lastPathComponent
        return "\(stem.isEmpty ? "transcript" : stem).\(format.fileExtension)"
    }

    private func handleError(_ error: Error) {
        let message = ErrorMapper.userMessage(for: error)
        errorMessage = message
        uiState = .error(message)
        AppLogger.error(message, logger: AppLogger.general)
    }
}

import UniformTypeIdentifiers
