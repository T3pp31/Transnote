import AVFoundation
import SwiftUI

@MainActor
final class MainWindowViewModel: ObservableObject {
    @Published var uiState: TranscriptionUIState = .idle
    @Published var progressDisplay: TranscriptionProgressDisplay = .idle()
    @Published var selectedFile: AudioFileInfo?
    @Published var transcriptText: String = ""
    @Published var currentTranscript: Transcript?
    @Published var playingSegmentID: UUID?
    @Published var isEditingTranscript = false
    @Published var errorMessage: String?
    @Published var inlineErrorTitle: String?
    @Published var inlineErrorMessage: String?
    @Published var canRetryError = false
    @Published var criticalErrorTitle: String?
    @Published var criticalErrorMessage: String?
    @Published var downloadedModelIDs: Set<String> = []
    @Published var isDownloadingModel = false
    @Published var toast: ToastMessage?

    private enum RecoverableAction: Equatable {
        case transcription
        case modelDownload
        case fileImport(url: URL, preferredFileName: String?)
        case export(format: ExportFormat)
    }

    private enum ErrorContext {
        case fileImport(url: URL, preferredFileName: String?)
        case transcription
        case modelDownload
        case export(ExportFormat)
        case general
    }

    private var lastRecoverableAction: RecoverableAction?
    private var activeJobID: UUID?
    private var activeModelDownloadID: UUID?
    private var transcriptionTask: Task<Void, Never>?
    private var modelDownloadTask: Task<Void, Never>?
    private var lastAnnouncedPhase: TranscriptionProgressPhase?
    private var toastDismissTask: Task<Void, Never>?

    private let transcriber: Transcriber
    private let audioFileService: AudioFileService
    private let audioImportService: AudioImportService
    private let exportService: ExportService
    private let fileAccess: SecurityScopedFileAccess
    private let settings: AppSettings
    private let modelAvailability: ModelAvailabilityService
    private let modelDownloadService: ModelDownloadService
    private let audioPlayer: AudioPlayerService

    init(
        transcriber: Transcriber = WhisperKitTranscriber(),
        audioFileService: AudioFileService = AudioFileService(),
        audioImportService: AudioImportService = AudioImportService(),
        exportService: ExportService = ExportService(),
        fileAccess: SecurityScopedFileAccess = .shared,
        settings: AppSettings = .shared,
        modelAvailability: ModelAvailabilityService = ModelAvailabilityService(),
        modelDownloadService: ModelDownloadService = ModelDownloadService(),
        audioPlayer: AudioPlayerService? = nil
    ) {
        self.transcriber = transcriber
        self.audioFileService = audioFileService
        self.audioImportService = audioImportService
        self.exportService = exportService
        self.fileAccess = fileAccess
        self.settings = settings
        self.modelAvailability = modelAvailability
        self.modelDownloadService = modelDownloadService
        self.audioPlayer = audioPlayer ?? AudioPlayerService()
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

    var startTranscriptionDisabledReason: String? {
        if isBusy {
            return NSLocalizedString("文字起こし処理中です", comment: "Transcription is busy")
        }
        if selectedFile == nil {
            return NSLocalizedString("音声ファイルを選択してください", comment: "Select an audio file")
        }
        if settings.selectedModel == nil {
            return NSLocalizedString("モデルを選択してください", comment: "Select a model")
        }
        if let model = settings.selectedModel, !isModelDownloaded(model) {
            return NSLocalizedString("モデルをダウンロードしてください", comment: "Download the selected model")
        }
        return nil
    }

    var modelDownloadDisabledReason: String? {
        if isBusy {
            return NSLocalizedString("処理中です", comment: "Operation in progress")
        }
        if settings.selectedModel == nil {
            return NSLocalizedString("モデルを選択してください", comment: "Select a model")
        }
        return nil
    }

    var shouldShowModelDownloadButton: Bool {
        guard let model = settings.selectedModel else {
            return false
        }
        return !isModelDownloaded(model)
    }

    var modelDownloadGuidance: String? {
        shouldShowModelDownloadButton
            ? NSLocalizedString(
                "初回はモデルのダウンロードが必要です（音声は端末内で処理し、通信はダウンロード時のみ）",
                comment: "Model download onboarding guidance"
            )
            : nil
    }

    var canCancel: Bool {
        isBusy
    }

    var cancelActionAccessibilityLabel: String {
        if isDownloadingModel {
            return NSLocalizedString("ダウンロードをキャンセル", comment: "Cancel model download accessibility label")
        }
        return NSLocalizedString("文字起こしをキャンセル", comment: "Cancel transcription accessibility label")
    }

    var cancelActionHelp: String {
        if isDownloadingModel {
            return NSLocalizedString("ダウンロードをキャンセル（Esc）", comment: "Cancel model download shortcut help")
        }
        return NSLocalizedString("文字起こしをキャンセル（Esc）", comment: "Cancel transcription shortcut help")
    }

    var cancelMenuTitle: String {
        cancelActionAccessibilityLabel
    }

    var canExport: Bool {
        currentTranscript != nil && !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canCopyTranscript: Bool {
        canExport
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

    func modelDownloadSuccessToastMessage() -> String {
        if selectedFile != nil {
            return NSLocalizedString(
                "モデルのダウンロードが完了しました。文字起こしを開始できます。",
                comment: "Model download success toast when file is selected"
            )
        }
        return NSLocalizedString(
            "モデルのダウンロードが完了しました。音声ファイルを選択してください。",
            comment: "Model download success toast when no file is selected"
        )
    }

    func downloadSelectedModel() {
        guard let model = settings.selectedModel,
              canDownloadSelectedModel else {
            return
        }

        let downloadID = UUID()
        activeModelDownloadID = downloadID
        clearErrors()
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
                        guard self.activeModelDownloadID == downloadID else { return }
                        self.applyModelDownloadProgress(update)
                    }
                }

                refreshModelAvailability()
                if activeModelDownloadID == downloadID {
                    uiState = .idle
                    progressDisplay = .idle()
                    announcePhaseIfNeeded(.finished)
                    showToast(modelDownloadSuccessToastMessage())
                    AppLogger.info("Model download completed: \(model.displayName)", logger: AppLogger.transcription)
                }
            } catch {
                if activeModelDownloadID == downloadID, !Task.isCancelled {
                    handleError(error, context: .modelDownload)
                }
            }

            if activeModelDownloadID == downloadID {
                activeModelDownloadID = nil
                isDownloadingModel = false
                modelDownloadTask = nil
            }
        }
    }

    @Published var confirmFileImport = false
    @Published var pendingFileImport: (url: URL, preferredFileName: String?)?

    var hasExistingResult: Bool {
        (currentTranscript?.fullText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
    }

    func selectFile(url: URL, preferredFileName: String? = nil) {
        clearErrors()

        if hasExistingResult {
            pendingFileImport = (url, preferredFileName)
            confirmFileImport = true
            return
        }

        applyFileImport(url: url, preferredFileName: preferredFileName)
    }

    func applyPendingFileImport() {
        guard let pending = pendingFileImport else { return }
        confirmFileImport = false
        pendingFileImport = nil
        applyFileImport(url: pending.url, preferredFileName: pending.preferredFileName)
    }

    func cancelPendingFileImport() {
        confirmFileImport = false
        pendingFileImport = nil
    }

    private func applyFileImport(url: URL, preferredFileName: String?) {
        do {
            let resolvedPreferredFileName = preferredFileName ?? preferredImportFileName(for: url)
            let importedURL = try audioImportService.importFile(
                from: url,
                preferredFileName: resolvedPreferredFileName
            )
            let info = try audioFileService.validate(
                url: importedURL,
                preferredFileName: resolvedPreferredFileName
            )
            stopPlayback()
            isEditingTranscript = false
            currentTranscript = nil
            transcriptText = ""
            selectedFile = info
            uiState = .idle
            progressDisplay = .idle()
        } catch {
            handleError(error, context: .fileImport(url: url, preferredFileName: preferredFileName))
        }
    }

    private func preferredImportFileName(for url: URL) -> String? {
        let resolvedName = AudioFileNameResolver.resolve(sourceURL: url)
        guard resolvedName != url.lastPathComponent else {
            return nil
        }
        guard DropImportService.hasSupportedExtension(
            resolvedName,
            supportedExtensions: settings.supportedExtensions
        ) else {
            return nil
        }
        return resolvedName
    }

    func startTranscription() {
        guard let file = selectedFile,
              let model = settings.selectedModel else {
            let message = AppError.invalidConfiguration.errorDescription
                ?? NSLocalizedString("アプリ設定が不正です。", comment: "Invalid configuration")
            presentCriticalError(
                title: NSLocalizedString("設定エラー", comment: "Configuration error title"),
                message: message
            )
            return
        }

        guard isModelDownloaded(model) else {
            let message = AppError.modelNotDownloaded(model.displayName).errorDescription
                ?? NSLocalizedString(
                    "モデルがダウンロードされていません。",
                    comment: "Model is not downloaded"
            )
            presentInlineError(
                title: NSLocalizedString("モデル未ダウンロード", comment: "Model not downloaded title"),
                message: message,
                canRetry: false,
                action: nil
            )
            return
        }

        settings.persist()
        clearErrors()
        stopPlayback()
        isEditingTranscript = false
        transcriptText = ""
        currentTranscript = nil
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
                var transcript = try await transcriber.transcribe(job) { update in
                    Task { @MainActor in
                        guard self.activeJobID == job.id else { return }
                        self.applyProgressUpdate(update)
                    }
                }

                transcript = await Self.transcriptWithPlaybackSegments(
                    transcript,
                    audioURL: file.url
                )

                guard activeJobID == job.id else { return }
                currentTranscript = transcript
                transcriptText = TranscriptTextSanitizer.presentableText(from: transcript.fullText)
                    ?? TranscriptTextSanitizer.sanitize(transcript.fullText)
                isEditingTranscript = false
                audioPlayer.load(url: file.url)
                uiState = .done
                progressDisplay = .done()
                refreshModelAvailability()
                announcePhaseIfNeeded(.finished)
                AppLogger.info("Transcription completed for \(file.fileName)", logger: AppLogger.transcription)
            } catch {
                if activeJobID == job.id, !Task.isCancelled {
                    handleError(error, context: .transcription)
                }
            }

            if activeJobID == job.id {
                activeJobID = nil
                transcriptionTask = nil
            }
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
        activeModelDownloadID = nil
        isDownloadingModel = false

        uiState = .idle
        progressDisplay = .idle()
        lastAnnouncedPhase = nil
    }

    func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptText, forType: .string)
        showToast(NSLocalizedString("文字起こし結果をコピーしました", comment: "Transcript copied toast"))
    }

    func showToast(_ text: String, icon: String = "checkmark.circle.fill", action: (label: String, handler: @Sendable () -> Void)? = nil) {
        toastDismissTask?.cancel()
        toast = ToastMessage(text: text, icon: icon, action: action)
        // Action buttons need a longer window so users can click before auto-dismiss.
        let dismissNanoseconds: UInt64 = action == nil ? 2_500_000_000 : 7_000_000_000
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: dismissNanoseconds)
            if !Task.isCancelled {
                toast = nil
            }
        }
    }

    private func dismissToast() {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        toast = nil
    }

    func playSegment(_ segment: TranscriptSegment) {
        guard let file = selectedFile else { return }

        if audioPlayer.loadedURL != file.url {
            audioPlayer.load(url: file.url)
        }

        playingSegmentID = segment.id
        let segmentID = segment.id
        audioPlayer.playSegment(
            start: segment.startTime,
            end: segment.endTime
        ) { [weak self] in
            guard let self else { return }
            if self.playingSegmentID == segmentID {
                self.playingSegmentID = nil
            }
        }
    }

    func stopPlayback() {
        audioPlayer.stop()
        playingSegmentID = nil
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
            showToast(
                String(
                    format: NSLocalizedString("保存しました: %@", comment: "Export completed toast"),
                    url.lastPathComponent
                ),
                action: (
                    label: NSLocalizedString("Finder で表示", comment: "Reveal in Finder toast action"),
                    handler: { [weak self] in
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        Task { @MainActor in
                            self?.dismissToast()
                        }
                    }
                )
            )
            AppLogger.info("Exported \(format.displayName) to \(url.lastPathComponent)", logger: AppLogger.export)
        } catch {
            handleError(error, context: .export(format))
        }
    }

    func dismissInlineError() {
        inlineErrorTitle = nil
        inlineErrorMessage = nil
        canRetryError = false
        lastRecoverableAction = nil
        if criticalErrorMessage == nil {
            errorMessage = nil
        }
        if case .error = uiState {
            uiState = .idle
        }
    }

    func dismissCriticalError() {
        criticalErrorTitle = nil
        criticalErrorMessage = nil
        errorMessage = nil
        uiState = .idle
    }

    func retryLastAction() {
        guard let action = lastRecoverableAction else { return }
        clearErrors()
        switch action {
        case .transcription:
            startTranscription()
        case .modelDownload:
            downloadSelectedModel()
        case .fileImport(let url, let preferredFileName):
            selectFile(url: url, preferredFileName: preferredFileName)
        case .export(let format):
            exportTranscript(format: format)
        }
    }

    private func applyModelDownloadProgress(_ update: TranscriptionProgressUpdate) {
        progressDisplay = TranscriptionProgressDisplay.from(update: update)
        uiState = .preparing
        announcePhaseIfNeeded(update.phase)
    }

    private func applyProgressUpdate(_ update: TranscriptionProgressUpdate) {
        progressDisplay = TranscriptionProgressDisplay.from(update: update)

        if let partialText = update.partialText,
           let presentable = TranscriptTextSanitizer.presentableText(from: partialText) {
            transcriptText = presentable
        }

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
        AccessibilityNotification.Announcement(phase.localizedDisplayName).post()
    }

    private func defaultExportFilename(for transcript: Transcript, format: ExportFormat) -> String {
        let stem = URL(fileURLWithPath: transcript.sourceFileName).deletingPathExtension().lastPathComponent
        return "\(stem.isEmpty ? "transcript" : stem).\(format.fileExtension)"
    }

    private func clearErrors() {
        errorMessage = nil
        inlineErrorTitle = nil
        inlineErrorMessage = nil
        canRetryError = false
        criticalErrorTitle = nil
        criticalErrorMessage = nil
        lastRecoverableAction = nil
    }

    private func presentInlineError(
        title: String,
        message: String,
        canRetry: Bool,
        action: RecoverableAction?
    ) {
        errorMessage = message
        inlineErrorTitle = title
        inlineErrorMessage = message
        canRetryError = canRetry
        lastRecoverableAction = canRetry ? action : nil
        criticalErrorTitle = nil
        criticalErrorMessage = nil
        uiState = .idle
    }

    private func presentCriticalError(title: String, message: String) {
        errorMessage = message
        criticalErrorTitle = title
        criticalErrorMessage = message
        inlineErrorTitle = nil
        inlineErrorMessage = nil
        canRetryError = false
        lastRecoverableAction = nil
        if uiState != .preparing && uiState != .transcribing {
            uiState = .idle
        }
    }

    private func handleError(_ error: Error, context: ErrorContext) {
        let message = ErrorMapper.userMessage(for: error)

        if isCriticalError(error) {
            presentCriticalError(title: criticalTitle(for: error), message: message)
        } else {
            let info = inlineErrorInfo(for: error, context: context)
            presentInlineError(
                title: info.title,
                message: message,
                canRetry: info.canRetry,
                action: info.action
            )
        }

        AppLogger.error(message, logger: AppLogger.general)
    }

    private func isCriticalError(_ error: Error) -> Bool {
        guard let appError = error as? AppError else { return false }
        switch appError {
        case .invalidConfiguration, .bookmarkResolutionFailed:
            return true
        default:
            return false
        }
    }

    private func criticalTitle(for error: Error) -> String {
        guard let appError = error as? AppError else {
            return NSLocalizedString("エラー", comment: "Generic error title")
        }
        switch appError {
        case .invalidConfiguration:
            return NSLocalizedString("設定エラー", comment: "Configuration error title")
        case .bookmarkResolutionFailed:
            return NSLocalizedString("ファイルアクセスエラー", comment: "File access error title")
        default:
            return NSLocalizedString("エラー", comment: "Generic error title")
        }
    }

    private func inlineErrorInfo(
        for error: Error,
        context: ErrorContext
    ) -> (title: String, canRetry: Bool, action: RecoverableAction?) {
        switch context {
        case .fileImport(let url, let preferredFileName):
            return (
                NSLocalizedString("ファイルの読み込みエラー", comment: "File import error title"),
                true,
                .fileImport(url: url, preferredFileName: preferredFileName)
            )
        case .transcription:
            return (NSLocalizedString("文字起こしエラー", comment: "Transcription error title"), true, .transcription)
        case .modelDownload:
            return (
                NSLocalizedString("モデルのダウンロードエラー", comment: "Model download error title"),
                true,
                .modelDownload
            )
        case .export(let format):
            return (NSLocalizedString("エクスポートエラー", comment: "Export error title"), true, .export(format: format))
        case .general:
            if let appError = error as? AppError, case .modelNotDownloaded = appError {
                return (NSLocalizedString("モデル未ダウンロード", comment: "Model not downloaded title"), false, nil)
            }
            return (NSLocalizedString("エラー", comment: "Generic error title"), false, nil)
        }
    }

    private static func transcriptWithPlaybackSegments(
        _ transcript: Transcript,
        audioURL: URL
    ) async -> Transcript {
        let segments = transcript.segments.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard segments.isEmpty,
              !transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            var updated = transcript
            updated.segments = segments
            return updated
        }

        let asset = AVURLAsset(url: audioURL)
        guard let duration = try? await asset.load(.duration).seconds,
              duration > 0 else {
            return transcript
        }

        var updated = transcript
        updated.segments = [
            TranscriptSegment(
                startTime: 0,
                endTime: duration,
                text: transcript.fullText
            )
        ]
        return updated
    }
}

import UniformTypeIdentifiers
