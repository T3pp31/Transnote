@MainActor
final class OperationCoordinator {
    enum Operation: Equatable {
        case importing
        case transcription
        case modelDownload
        case playback
    }

    private(set) var activeOperation: Operation?

    func canStart(_ operation: Operation) -> Bool {
        activeOperation == nil || activeOperation == operation
    }

    @discardableResult
    func start(_ operation: Operation) -> Bool {
        guard canStart(operation) else { return false }
        activeOperation = operation
        return true
    }

    func end(_ operation: Operation) {
        if activeOperation == operation {
            activeOperation = nil
        }
    }
}

import AVFoundation
import SwiftUI

// MARK: - Model download coordination

@MainActor
final class ModelDownloadCoordinator {
    struct State {
        var isDownloading = false
        var activeID: UUID?
    }

    private(set) var state = State()

    func begin() -> UUID? {
        guard !state.isDownloading else { return nil }
        let id = UUID()
        state.isDownloading = true
        state.activeID = id
        return id
    }

    func finish(_ id: UUID) {
        guard state.activeID == id else { return }
        state.isDownloading = false
        state.activeID = nil
    }

    func isActive(_ id: UUID) -> Bool {
        state.activeID == id && state.isDownloading
    }
}

@MainActor
struct AppDependencies {

    var transcriber: any Transcriber = WhisperKitTranscriber()
    var audioFileService: AudioFileService = AudioFileService()
    var audioImportService: AudioImportService = AudioImportService()
    var exportService: ExportService = ExportService()
    var fileAccess: SecurityScopedFileAccess = .shared
    var settings: AppSettings = AppSettings.shared
    var modelAvailability: ModelAvailabilityService = ModelAvailabilityService()
    var modelDownloadService: ModelDownloadService = ModelDownloadService()
    var audioPlayer: AudioPlayerService? = nil
    var historyStore: HistoryStore = HistoryStore()
    var savePanelPresenter: any SavePanelPresenting = NSSavePanelPresenter()

    static let shared = AppDependencies()
}

@MainActor
final class MainWindowViewModel: ObservableObject {
    @Published var uiState: TranscriptionUIState = .idle
    @Published var progressDisplay: TranscriptionProgressDisplay = .idle()
    @Published var selectedFile: AudioFileInfo? {
        didSet {
            refreshSelectedFileAvailability()
        }
    }
    /// SwiftUI body の再評価ごとに同期 fileExists を呼ばないよう、選択ファイルの存在確認結果を保持する。
    @Published private(set) var isSelectedFileAvailable = false
    private var storedTranscriptText: String = ""
    /// セグメント編集中は `storedTranscript.fullText` を唯一の本文バッファとして共有し、
    /// `transcriptText` 側との参照共有による全文 COW コピーと全走査比較を避ける。
    private var isTranscriptTextSyncedToStoredTranscript = false

    var transcriptText: String {
        get {
            if isTranscriptTextSyncedToStoredTranscript {
                if let draft = activeSegmentDraft {
                    return draft.fullText
                }
                return storedTranscript?.fullText ?? storedTranscriptText
            }
            return storedTranscriptText
        }
        set {
            let currentText = transcriptText
            if newValue == currentText {
                return
            }
            commitActiveSegmentDraftIfNeeded()
            objectWillChange.send()
            isTranscriptTextSyncedToStoredTranscript = false
            storedTranscriptText = newValue
            // 全文の trimmed 文字列を生成せず、最初の非空白文字で早期終了する。
            hasNonEmptyTranscriptText = Self.containsNonWhitespaceScalar(newValue)
        }
    }

    private var storedTranscript: Transcript?

    var currentTranscript: Transcript? {
        get {
            guard var transcript = storedTranscript else { return nil }
            if let draft = activeSegmentDraft {
                transcript.segments[draft.index].text = draft.text
                transcript.fullText = draft.fullText
            }
            return transcript
        }
        set {
            objectWillChange.send()
            if isTranscriptTextSyncedToStoredTranscript {
                if let draft = activeSegmentDraft {
                    storedTranscriptText = draft.fullText
                } else {
                    storedTranscriptText = storedTranscript?.fullText ?? storedTranscriptText
                }
                isTranscriptTextSyncedToStoredTranscript = false
            }
            activeSegmentDraft = nil
            storedTranscript = newValue
        }
    }
    @Published var baselineTranscriptText: String = ""
    @Published var playingSegmentID: UUID?
    @Published var playbackPositionText: String = ""
    @Published var isSegmentPaused = false
    @Published var isEditingTranscript = false
    @Published var errorMessage: String?
    @Published var inlineErrorTitle: String?
    @Published var inlineErrorMessage: String?
    @Published var canRetryError = false
    @Published var criticalErrorTitle: String?
    @Published var criticalErrorMessage: String?
    @Published var downloadedModelIDs: Set<String> = []
    /// モデルごとの表示用ディスク使用量キャッシュ。SwiftUI body 評価中に同期走査しないために保持する。
    @Published private(set) var modelDiskUsageByID: [String: String] = [:]
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
    private var activeImportID: UUID?
    private(set) var transcriptionTask: Task<Void, Never>?
    private var modelDownloadTask: Task<Void, Never>?
    private(set) var importTask: Task<Void, Never>?
    private(set) var modelDiskUsageTask: Task<Void, Never>?
    private var modelDiskUsageGeneration = 0
    private var lastAnnouncedPhase: TranscriptionProgressPhase?
    private var toastDismissTask: Task<Void, Never>?
    private var hasSegmentTextEdits = false
    /// transcriptText 更新時に算出する。body 再評価のたびに全文を trimming しないため。
    private var hasNonEmptyTranscriptText = false

    private struct ActiveSegmentDraft {
        let id: UUID
        let index: Int
        var text: String
        let prefix: String
        let suffix: String
        let prefixHasNonWhitespace: Bool
        let suffixHasNonWhitespace: Bool

        var fullText: String {
            var combined = String()
            combined.reserveCapacity(prefix.utf8.count + text.utf8.count + suffix.utf8.count)
            combined.append(prefix)
            combined.append(text)
            combined.append(suffix)
            return combined
        }
    }

    // セグメント編集中は Transcript 全体や segments 配列を毎入力でコピーせず、
    // 編集対象セグメントの可変ドラフトだけを O(1) で更新し、切り替え・確定時に反映する。
    private var activeSegmentDraft: ActiveSegmentDraft?

    private let modelDownloadCoordinator = ModelDownloadCoordinator()

    private let transcriber: Transcriber
    private let audioFileService: AudioFileService
    private let audioImportService: AudioImportService
    private let exportService: ExportService
    private let fileAccess: SecurityScopedFileAccess
    private let savePanelPresenter: any SavePanelPresenting
    private let settings: any AppSettingsProviding
    private let modelAvailability: ModelAvailabilityService
    private let modelDownloadService: ModelDownloadService
    private let audioPlayer: AudioPlayerService
    private let historyStore: HistoryStore
    private let fileExistsChecker: (String) -> Bool

    init(
        transcriber: Transcriber = WhisperKitTranscriber(),
        audioFileService: AudioFileService = AudioFileService(),
        audioImportService: AudioImportService = AudioImportService(),
        exportService: ExportService = ExportService(),
        fileAccess: SecurityScopedFileAccess = .shared,
        savePanelPresenter: any SavePanelPresenting = NSSavePanelPresenter(),
        settings: any AppSettingsProviding = AppSettings.shared,
        modelAvailability: ModelAvailabilityService = ModelAvailabilityService(),
        modelDownloadService: ModelDownloadService = ModelDownloadService(),
        audioPlayer: AudioPlayerService? = nil,
        historyStore: HistoryStore = HistoryStore(),
        fileExistsChecker: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.transcriber = transcriber
        self.audioFileService = audioFileService
        self.audioImportService = audioImportService
        self.exportService = exportService
        self.fileAccess = fileAccess
        self.savePanelPresenter = savePanelPresenter
        self.settings = settings
        self.modelAvailability = modelAvailability
        self.modelDownloadService = modelDownloadService
        self.audioPlayer = audioPlayer ?? AudioPlayerService()
        self.historyStore = historyStore
        self.fileExistsChecker = fileExistsChecker
        configureAudioPlayerCallbacks()
        refreshModelAvailability()
    }

    /// AppDependencies 経由で依存をまとめて注入するイニシャライザ。
    init(
        dependencies: AppDependencies,
        fileExistsChecker: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.transcriber = dependencies.transcriber
        self.audioFileService = dependencies.audioFileService
        self.audioImportService = dependencies.audioImportService
        self.exportService = dependencies.exportService
        self.fileAccess = dependencies.fileAccess
        self.savePanelPresenter = dependencies.savePanelPresenter
        self.settings = dependencies.settings
        self.modelAvailability = dependencies.modelAvailability
        self.modelDownloadService = dependencies.modelDownloadService
        self.audioPlayer = dependencies.audioPlayer ?? AudioPlayerService()
        self.historyStore = dependencies.historyStore
        self.fileExistsChecker = fileExistsChecker
        configureAudioPlayerCallbacks()
        refreshModelAvailability()
    }

    private func configureAudioPlayerCallbacks() {
        audioPlayer.onPlaybackTimeUpdate = { [weak self] current, duration in
            Task { @MainActor in
                self?.updatePlaybackPosition(current: current, duration: duration)
            }
        }
    }

    private let operationCoordinator = OperationCoordinator()

    /// モデルダウンロード中かどうか。uiState + progressDisplay から導出する単一の状態。
    var isDownloadingModel: Bool {
        uiState == .preparing && progressDisplay.phase == .downloadingModel
    }

    /// 音声ファイルの非同期取り込み中かどうか。
    var isImportingFile: Bool {
        operationCoordinator.activeOperation == .importing
    }

    /// テスト専用: モデルダウンロード中の状態をシミュレートする。
    /// 本番コードでは使用しない（状態機械の整合性を保つため）。
    func simulateModelDownloadForTesting() {
        guard operationCoordinator.start(.modelDownload) else { return }
        uiState = .preparing
        progressDisplay = TranscriptionProgressDisplay.from(update: .make(phase: .downloadingModel, fraction: 0))
    }

    var isBusy: Bool {
        operationCoordinator.activeOperation != nil || isDownloadingModel
    }

    /// 選択中ファイルの存在確認結果を更新する。ファイル選択・取り込み完了・アプリ復帰・実行直前に呼ぶ。
    func refreshSelectedFileAvailability() {
        guard let selectedFile else {
            isSelectedFileAvailable = false
            return
        }
        isSelectedFileAvailable = fileExistsChecker(selectedFile.url.path)
    }

    /// 選択中のファイルが実在する場合だけ返す。body 評価時はキャッシュ済み状態のみを参照する。
    var existingSelectedFile: AudioFileInfo? {
        guard let selectedFile, isSelectedFileAvailable else {
            return nil
        }
        return selectedFile
    }

    var canStartTranscription: Bool {
        startTranscriptionDisabledReason == nil
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
        if existingSelectedFile == nil {
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
            return NSLocalizedString("ダウンロードをキャンセル（⌘.）", comment: "Cancel model download shortcut help")
        }
        return NSLocalizedString("文字起こしをキャンセル（⌘.）", comment: "Cancel transcription shortcut help")
    }

    var cancelMenuTitle: String {
        cancelActionAccessibilityLabel
    }

    var canExport: Bool {
        currentTranscript != nil && hasNonEmptyTranscriptText
    }

    var canCopyTranscript: Bool {
        canExport
    }

    static func hasPlayableSegments(in transcript: Transcript) -> Bool {
        transcript.segments.contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// クラッシュ復旧用の一時 Transcript を取得する。
    func temporaryTranscriptForRecovery() -> Transcript? {
        historyStore.loadTemporary()
    }

    /// 復旧用一時 Transcript を削除する。
    func clearTemporaryTranscript() {
        historyStore.clearTemporary()
    }

    /// クラッシュ復旧用の一時 Transcript を現在の状態へ復元する。
    func restoreTranscript(_ transcript: Transcript) {
        currentTranscript = transcript
        baselineTranscriptText = transcript.fullText
        transcriptText = transcript.fullText
        isEditingTranscript = !Self.hasPlayableSegments(in: transcript)
        hasSegmentTextEdits = false
        uiState = .done
        progressDisplay = .done()
        confirmFileImport = false
        pendingFileImport = nil
    }

    func refreshModelAvailability() {
        downloadedModelIDs = Set(
            settings.models
                .filter { modelAvailability.isDownloaded(whisperKitModelName: $0.whisperKitModelName) }
                .map(\.id)
        )
        modelDiskUsageGeneration += 1
        modelDiskUsageTask?.cancel()
        modelDiskUsageTask = nil
        modelDiskUsageByID.removeAll()
    }

    func isModelDownloaded(_ model: ModelOption) -> Bool {
        downloadedModelIDs.contains(model.id)
    }

    /// 選択中モデルがダウンロード済みの場合に削除する。
    func deleteSelectedModel() {
        guard let model = settings.selectedModel,
              isModelDownloaded(model) else { return }
        do {
            try modelDownloadService.deleteModel(whisperKitModelName: model.whisperKitModelName)
            refreshModelAvailability()
            showToast(
                String(
                    format: NSLocalizedString("モデル「%@」を削除しました", comment: "Model deleted toast"),
                    model.displayName
                )
            )
        } catch {
            handleError(error, context: .general)
        }
    }

    /// モデルの使用ディスク容量のキャッシュ済み表示テキストを返す。未ダウンロードまたは未算出の場合は nil。
    func modelDiskUsageText(_ model: ModelOption) -> String? {
        guard isModelDownloaded(model) else { return nil }
        return modelDiskUsageByID[model.id]
    }

    /// 指定モデルのディスク使用量をバックグラウンドで再計算し、表示用キャッシュを更新する。
    func refreshModelDiskUsage(for model: ModelOption) {
        guard isModelDownloaded(model) else {
            modelDiskUsageByID.removeValue(forKey: model.id)
            return
        }
        modelDiskUsageGeneration += 1
        let generation = modelDiskUsageGeneration
        let modelID = model.id
        let modelName = model.whisperKitModelName
        let availability = modelAvailability
        modelDiskUsageTask?.cancel()
        modelDiskUsageTask = Task { [weak self] in
            let bytes = await Task.detached(priority: .utility) {
                availability.diskUsage(whisperKitModelName: modelName)
            }.value
            guard let self,
                  !Task.isCancelled,
                  self.modelDiskUsageGeneration == generation,
                  self.downloadedModelIDs.contains(modelID) else {
                return
            }
            self.modelDiskUsageByID[modelID] = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            self.modelDiskUsageTask = nil
        }
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
              canDownloadSelectedModel,
              operationCoordinator.start(.modelDownload) else {
            return
        }

        let downloadID = UUID()
        activeModelDownloadID = downloadID
        clearErrors()
        uiState = .preparing
        progressDisplay = TranscriptionProgressDisplay.from(
            update: .make(phase: .downloadingModel, fraction: 0, modelDisplayName: model.localizedDisplayName)
        )
        lastAnnouncedPhase = nil

        modelDownloadTask = Task {
            do {
                _ = try await modelDownloadService.downloadIfNeeded(
                    whisperKitModelName: model.whisperKitModelName,
                    modelDisplayName: model.localizedDisplayName
                ) { update in
                    Task { @MainActor in
                        guard self.activeModelDownloadID == downloadID else { return }
                        self.applyModelDownloadProgress(update)
                    }
                }

                refreshModelAvailability()
                if activeModelDownloadID == downloadID {
                    let hasResult = currentTranscript != nil
                    uiState = hasResult ? .done : .idle
                    progressDisplay = hasResult ? .done() : .idle()
                    announcePhaseIfNeeded(.finished)
                    showToast(modelDownloadSuccessToastMessage())
                    AppLogger.info("Model download completed: \(model.displayName)", logger: AppLogger.transcription)
                }
            } catch {
                if activeModelDownloadID == downloadID, !Task.isCancelled {
                    let hasResult = currentTranscript != nil
                    handleError(error, context: .modelDownload)
                    if hasResult {
                        uiState = .done
                        progressDisplay = .done()
                    }
                }
            }

            if activeModelDownloadID == downloadID {
                activeModelDownloadID = nil
                modelDownloadTask = nil
                operationCoordinator.end(.modelDownload)
            }
        }
    }

    @Published var confirmFileImport = false
    @Published var pendingFileImport: (url: URL, preferredFileName: String?)?
    private var isPendingTranscriptionRestart = false

    var hasExistingResult: Bool {
        (currentTranscript?.fullText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
    }

    /// 編集モードで内容が元の文字起こしから変わっているかを表す。
    /// ウィンドウ終了・ファイル差し替え前に確認するための dirty 状態。
    var hasUnsavedChanges: Bool {
        guard currentTranscript != nil else { return false }
        let normalizedEdited = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBaseline = baselineTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedEdited != normalizedBaseline
    }

    func selectFile(url: URL, preferredFileName: String? = nil) {
        // 文字起こし・モデルダウンロード中のファイル差し替えは禁止する。
        guard !isBusy else {
            AppLogger.info("File selection ignored while busy", logger: AppLogger.fileAccess)
            return
        }

        clearErrors()

        if hasExistingResult || hasUnsavedChanges {
            pendingFileImport = (url, preferredFileName)
            confirmFileImport = true
            return
        }

        applyFileImport(url: url, preferredFileName: preferredFileName)
    }

    func applyPendingFileImport() {
        let shouldStartTranscription = isPendingTranscriptionRestart
        let pending = pendingFileImport
        cancelPendingFileImport()
        if let pending {
            // インポート失敗・キャンセル時に旧ファイルへ再文字起こししないよう、
            // 非同期インポートの成功後にのみ文字起こしを開始する。
            applyFileImport(
                url: pending.url,
                preferredFileName: pending.preferredFileName,
                startTranscriptionAfterImport: shouldStartTranscription
            )
            return
        }
        if shouldStartTranscription {
            startTranscription(replacingExistingResult: true)
        }
    }

    func cancelPendingFileImport() {
        confirmFileImport = false
        pendingFileImport = nil
        isPendingTranscriptionRestart = false
    }

    /// 進行中のファイル取り込みをキャンセルし、直前の選択状態・結果を保持する。
    func cancelFileImport() {
        let wasImporting = operationCoordinator.activeOperation == .importing
        importTask?.cancel()
        importTask = nil
        activeImportID = nil
        if wasImporting {
            operationCoordinator.end(.importing)
            uiState = currentTranscript != nil ? .done : .idle
            progressDisplay = currentTranscript != nil ? .done() : .idle()
        }
    }

    /// 進行中の操作（ファイル取り込み・モデルダウンロード・文字起こし）に応じてキャンセルする。
    func cancelCurrentOperation() {
        if isImportingFile {
            cancelFileImport()
        } else if isDownloadingModel {
            cancelModelDownload()
        } else {
            cancelTranscription()
        }
    }

    private func applyFileImport(
        url: URL,
        preferredFileName: String?,
        startTranscriptionAfterImport: Bool = false
    ) {
        guard operationCoordinator.start(.importing) else {
            AppLogger.info("File import ignored while another operation is active", logger: AppLogger.fileAccess)
            return
        }

        let importID = UUID()
        activeImportID = importID
        let previousUIState = uiState
        let previousProgressDisplay = progressDisplay
        uiState = .preparing
        progressDisplay = TranscriptionProgressDisplay.from(
            update: .make(phase: .convertingAudio, fraction: 0)
        )

        let importService = audioImportService
        let fileService = audioFileService
        let supportedExtensions = settings.supportedExtensions

        importTask = Task {
            do {
                let outcome = try await Task.detached(priority: .userInitiated) { () throws -> (info: AudioFileInfo, createdCopy: URL?) in
                    try Task.checkCancellation()
                    let resolvedPreferredFileName = preferredFileName
                        ?? Self.preferredImportFileName(for: url, supportedExtensions: supportedExtensions)
                    let importedURL = try importService.importFile(
                        from: url,
                        preferredFileName: resolvedPreferredFileName
                    )
                    let createdCopy = importedURL.standardizedFileURL != url.standardizedFileURL
                        ? importedURL
                        : nil
                    do {
                        try Task.checkCancellation()
                        let info = try fileService.validate(
                            url: importedURL,
                            preferredFileName: resolvedPreferredFileName
                        )
                        return (info, createdCopy)
                    } catch {
                        if let createdCopy {
                            try? FileManager.default.removeItem(at: createdCopy)
                        }
                        throw error
                    }
                }.value

                guard activeImportID == importID, !Task.isCancelled else {
                    if let createdCopy = outcome.createdCopy {
                        try? FileManager.default.removeItem(at: createdCopy)
                    }
                    return
                }

                removePreviousSandboxCopyIfNeeded()
                stopPlayback()
                isEditingTranscript = false
                hasSegmentTextEdits = false
                currentTranscript = nil
                baselineTranscriptText = ""
                transcriptText = ""
                selectedFile = outcome.info
                uiState = .idle
                progressDisplay = .idle()
                activeImportID = nil
                importTask = nil
                operationCoordinator.end(.importing)

                if startTranscriptionAfterImport {
                    startTranscription(replacingExistingResult: true)
                }
            } catch {
                guard activeImportID == importID else { return }
                activeImportID = nil
                importTask = nil
                operationCoordinator.end(.importing)

                if Task.isCancelled || error is CancellationError {
                    uiState = previousUIState
                    progressDisplay = previousProgressDisplay
                } else {
                    uiState = previousUIState
                    progressDisplay = previousProgressDisplay
                    handleError(
                        error,
                        context: .fileImport(url: url, preferredFileName: preferredFileName),
                        preserveUIState: true
                    )
                }
            }
        }
    }

    /// ファイル差し替え時に、Imports/ 内に残った旧 sandbox コピーを削除する。
    /// 削除対象は薄い sandbox コピー（audioImportService.importsRoot 配下）のみに限定する。
    private func removePreviousSandboxCopyIfNeeded() {
        guard let previousURL = selectedFile?.url else { return }
        let importsPath = audioImportService.importsRoot.standardizedFileURL.path
        let previousPath = previousURL.standardizedFileURL.path
        guard previousPath.hasPrefix(importsPath + "/"),
              FileManager.default.fileExists(atPath: previousPath) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: previousURL)
            AppLogger.info(
                "Removed previous sandbox copy: \(previousURL.lastPathComponent)",
                logger: AppLogger.fileAccess
            )
        } catch {
            AppLogger.error(
                "Failed to remove previous sandbox copy: \(previousURL.lastPathComponent)",
                logger: AppLogger.fileAccess
            )
        }
    }

    private nonisolated static func preferredImportFileName(
        for url: URL,
        supportedExtensions: [String]
    ) -> String? {
        let resolvedName = AudioFileNameResolver.resolve(sourceURL: url)
        guard resolvedName != url.lastPathComponent else {
            return nil
        }
        guard DropImportService.hasSupportedExtension(
            resolvedName,
            supportedExtensions: supportedExtensions
        ) else {
            return nil
        }
        return resolvedName
    }

    func startTranscription() {
        startTranscription(replacingExistingResult: false)
    }

    private func startTranscription(replacingExistingResult: Bool) {
        guard operationCoordinator.activeOperation == nil else {
            presentInlineError(
                title: NSLocalizedString("処理中", comment: "Busy title"),
                message: NSLocalizedString("別の処理を実行中のため開始できません。", comment: "Busy message"),
                canRetry: false,
                action: nil,
                preserveUIState: true
            )
            return
        }

        if (hasExistingResult || hasUnsavedChanges) && !replacingExistingResult {
            isPendingTranscriptionRestart = true
            confirmFileImport = true
            return
        }

        refreshSelectedFileAvailability()

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

        guard isSelectedFileAvailable else {
            handleError(AppError.fileNotFound, context: .general)
            return
        }

        guard isModelDownloaded(model) else {
            let message = AppError.modelNotDownloaded(model.localizedDisplayName).errorDescription
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

        guard operationCoordinator.start(.transcription) else {
            presentInlineError(
                title: NSLocalizedString("処理中", comment: "Busy title"),
                message: NSLocalizedString("別の処理を実行中のため開始できません。", comment: "Busy message"),
                canRetry: false,
                action: nil,
                preserveUIState: true
            )
            return
        }

        settings.persist()
        clearErrors()
        stopPlayback()
        isEditingTranscript = false
        hasSegmentTextEdits = false
        transcriptText = ""
        currentTranscript = nil
        uiState = .preparing
        progressDisplay = TranscriptionProgressDisplay.from(
            update: .make(phase: .initializing, fraction: 0, modelDisplayName: model.localizedDisplayName)
        )
        lastAnnouncedPhase = nil

        let job = TranscriptionJob(
            audioFileURL: file.url,
            sourceFileName: file.fileName,
            modelID: model.id,
            whisperKitModelName: model.whisperKitModelName,
            modelDisplayName: model.localizedDisplayName,
            languageID: settings.selectedLanguageID,
            vadEnabled: settings.vadEnabled
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
                // エンコードと書き込みは MainActor 外で行うが、完了表示より前に
                // 保存完了を待つ（完了直後の終了で履歴・復旧データが失われないように）。
                let store = historyStore
                await Task.detached(priority: .utility) {
                    do {
                        try store.saveWithTemporary(transcript)
                    } catch {
                        AppLogger.error("Failed to save transcript: \(error.localizedDescription)", logger: AppLogger.transcription)
                    }
                }.value
                guard activeJobID == job.id else { return }
                currentTranscript = transcript
                baselineTranscriptText = transcript.fullText
                transcriptText = TranscriptTextSanitizer.presentableText(from: transcript.fullText)
                    ?? TranscriptTextSanitizer.sanitize(transcript.fullText)
                isEditingTranscript = !Self.hasPlayableSegments(in: transcript)
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
                operationCoordinator.end(.transcription)
                isPendingTranscriptionRestart = false
            }
        }
    }

    /// 現在実行中の操作（ファイル取り込み・モデルダウンロード・文字起こし）をキャンセルする。
    func cancelActiveOperation() {
        cancelCurrentOperation()
    }

    /// 文字起こしのみをキャンセルする（モデルDLは対象外）。
    func cancelTranscription() {
        if let jobID = activeJobID {
            Task { await transcriber.cancel(jobID: jobID) }
        }
        transcriptionTask?.cancel()
        transcriptionTask = nil
        activeJobID = nil
        operationCoordinator.end(.transcription)

        uiState = .idle
        progressDisplay = .idle()
        lastAnnouncedPhase = nil
    }

    /// モデルダウンロードのみをキャンセルする（文字起こしは対象外）。
    func cancelModelDownload() {
        let wasDownloading = operationCoordinator.activeOperation == .modelDownload
        modelDownloadTask?.cancel()
        modelDownloadTask = nil
        activeModelDownloadID = nil
        if wasDownloading {
            operationCoordinator.end(.modelDownload)
        }
        let hasResult = currentTranscript != nil
        uiState = hasResult ? .done : .idle
        progressDisplay = hasResult ? .done() : .idle()
        lastAnnouncedPhase = nil
        AccessibilityNotification.Announcement(
            NSLocalizedString("処理をキャンセルしました。", comment: "Accessibility announcement for cancellation")
        ).post()
    }

    /// Full Text 編集内容を currentTranscript の fullText と segments の両方に同期する。
    func updateTranscriptText(_ newText: String) {
        transcriptText = newText
        guard var transcript = currentTranscript else { return }
        transcript.applyFullTextEdit(newText)
        currentTranscript = transcript
    }

    private static func containsNonWhitespaceScalar(_ text: String) -> Bool {
        text.unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private func commitActiveSegmentDraftIfNeeded() {
        guard let draft = activeSegmentDraft, storedTranscript != nil else { return }
        storedTranscript!.segments[draft.index].text = draft.text
        storedTranscript!.fullText = draft.fullText
        activeSegmentDraft = nil
    }

    /// セグメントのテキストを更新し、currentTranscript と全文に同期する。
    /// 同一セグメントへの連続入力では編集用ドラフトバッファだけを O(1) で更新し、
    /// セグメント配列の COW コピーと全文の線形インデックス走査・再結合を回避する。
    func updateSegmentText(id: UUID, text: String) {
        guard storedTranscript != nil else { return }

        if var draft = activeSegmentDraft, draft.id == id {
            objectWillChange.send()
            draft.text = text
            activeSegmentDraft = draft
            hasSegmentTextEdits = true
            hasNonEmptyTranscriptText = draft.prefixHasNonWhitespace
                || draft.suffixHasNonWhitespace
                || Self.containsNonWhitespaceScalar(text)
            return
        }

        guard let index = storedTranscript?.segments.firstIndex(where: { $0.id == id }) else { return }

        // 別セグメントへ移動した場合は直前のドラフトを確定してから新しいドラフトを開始する。
        commitActiveSegmentDraftIfNeeded()
        let segments = storedTranscript!.segments
        let prefix = index > 0
            ? segments[..<index].map(\.text).joined(separator: "\n") + "\n"
            : ""
        let suffix = index + 1 < segments.count
            ? "\n" + segments[(index + 1)...].map(\.text).joined(separator: "\n")
            : ""

        objectWillChange.send()
        if !isTranscriptTextSyncedToStoredTranscript {
            storedTranscriptText = ""
            isTranscriptTextSyncedToStoredTranscript = true
        }

        let draft = ActiveSegmentDraft(
            id: id,
            index: index,
            text: text,
            prefix: prefix,
            suffix: suffix,
            prefixHasNonWhitespace: Self.containsNonWhitespaceScalar(prefix),
            suffixHasNonWhitespace: Self.containsNonWhitespaceScalar(suffix)
        )
        activeSegmentDraft = draft
        hasSegmentTextEdits = true
        hasNonEmptyTranscriptText = draft.prefixHasNonWhitespace
            || draft.suffixHasNonWhitespace
            || Self.containsNonWhitespaceScalar(text)
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
        refreshSelectedFileAvailability()
        guard let file = existingSelectedFile else {
            showToast(
                NSLocalizedString("音声ファイルが見つからないため再生できません", comment: "Audio file missing for playback"),
                icon: "exclamationmark.triangle.fill"
            )
            return
        }

        if audioPlayer.loadedURL != file.url {
            audioPlayer.load(url: file.url)
        }

        playingSegmentID = segment.id
        isSegmentPaused = false
        let segmentID = segment.id
        playbackPositionText = Self.remainingTimeText(
            current: 0,
            duration: segment.endTime - segment.startTime
        )
        audioPlayer.playSegment(
            start: segment.startTime,
            end: segment.endTime
        ) { [weak self] in
            guard let self else { return }
            if self.playingSegmentID == segmentID {
                self.playingSegmentID = nil
                self.isSegmentPaused = false
                self.playbackPositionText = ""
            }
        }
    }

    /// 現在の再生位置とセグメント長から残り時間を表示する。
    func updatePlaybackPosition(current: TimeInterval, duration: TimeInterval) {
        playbackPositionText = Self.remainingTimeText(current: current, duration: duration)
    }

    private static func remainingTimeText(current: TimeInterval, duration: TimeInterval) -> String {
        let remaining = max(0, duration - current)
        let totalSeconds = Int(remaining.rounded())
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    func pausePlayback() {
        audioPlayer.pause()
        isSegmentPaused = true
    }

    func resumePlayback() {
        audioPlayer.resume()
        isSegmentPaused = false
    }

    func stopPlayback() {
        audioPlayer.stop()
        playingSegmentID = nil
        isSegmentPaused = false
    }

    /// Imports のクリア後に、削除済みの sandbox コピーを参照し続けないようにする。
    func handleImportsCleared() {
        guard let file = selectedFile,
              file.url.standardizedFileURL.path.hasPrefix(
                AppDirectories.importsDirectory.standardizedFileURL.path + "/"
              ) else { return }
        stopPlayback()
        selectedFile = nil
    }

    func exportTranscript(format: ExportFormat) {
        guard var transcript = currentTranscript else { return }

        let savedExportDirectory = fileAccess.loadLastExportDirectory()
        var didBeginSavedDirectoryAccess = false

        if let savedDirectory = savedExportDirectory {
            do {
                try fileAccess.beginAccess(url: savedDirectory)
                didBeginSavedDirectoryAccess = true
            } catch {
                AppLogger.info(
                    "Skipped last export directory restore: \(error.localizedDescription)",
                    logger: AppLogger.fileAccess
                )
            }
        }

        defer {
            if didBeginSavedDirectoryAccess, let savedDirectory = savedExportDirectory {
                fileAccess.endAccess(url: savedDirectory)
            }
        }

        let url = savePanelPresenter.presentSavePanel(
            defaultFileName: defaultExportFilename(for: transcript, format: format),
            allowedContentTypes: [UTType(filenameExtension: format.fileExtension) ?? .plainText],
            initialDirectoryURL: didBeginSavedDirectoryAccess ? savedExportDirectory : nil
        )
        guard let url else { return }

        // 書き出し用のコピーに最新の編集内容を反映する（全文とセグメント字幕を同期）。
        if transcript.fullText != transcriptText {
            transcript.applyFullTextEdit(transcriptText)
        }
        transcript.updatedAt = Date()

        do {
            try exportService.write(transcript: transcript, format: format, to: url)
            // 書き出し成功後にのみ保存済み状態を確定し、失敗時は未保存変更を保持する。
            currentTranscript = transcript
            baselineTranscriptText = transcript.fullText
            fileAccess.saveLastExportDirectoryBookmark(for: url.deletingLastPathComponent())
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

        if let presentable = progressDisplay.presentablePartialText {
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
        action: RecoverableAction?,
        preserveUIState: Bool = false
    ) {
        errorMessage = message
        inlineErrorTitle = title
        inlineErrorMessage = message
        canRetryError = canRetry
        lastRecoverableAction = canRetry ? action : nil
        criticalErrorTitle = nil
        criticalErrorMessage = nil
        // 開始拒否の通知では進行中操作を維持し、実際の失敗時だけ待機状態に戻す。
        if !preserveUIState {
            uiState = .idle
        }
    }

    private func presentCriticalError(title: String, message: String, preserveUIState: Bool = false) {
        errorMessage = message
        criticalErrorTitle = title
        criticalErrorMessage = message
        inlineErrorTitle = nil
        inlineErrorMessage = nil
        canRetryError = false
        lastRecoverableAction = nil
        if !preserveUIState, uiState != .preparing && uiState != .transcribing {
            uiState = .idle
        }
    }

    private func handleError(_ error: Error, context: ErrorContext, preserveUIState: Bool = false) {
        let message = ErrorMapper.userMessage(for: error)

        // ログには元エラー（技術詳細）を記録し、ユーザー向けメッセージとは分離する。
        // 元エラーが AppError.transcriptionFailedWithReason / AppError.exportFailedWithReason の
        // 場合は元の reason を、それ以外は error 自体を記録する。
        let logError: Error
        if let appError = error as? AppError {
            switch appError {
            case .transcriptionFailedWithReason(let reason), .exportFailedWithReason(let reason):
                logError = reason
            default:
                logError = error
            }
        } else {
            logError = error
        }
        AppLogger.error("\(logError)", logger: AppLogger.general)

        if isCriticalError(error) {
            presentCriticalError(
                title: criticalTitle(for: error),
                message: message,
                preserveUIState: preserveUIState
            )
        } else {
            let info = inlineErrorInfo(for: error, context: context)
            presentInlineError(
                title: info.title,
                message: message,
                canRetry: info.canRetry,
                action: info.action,
                preserveUIState: preserveUIState
            )
        }
        // キャンセル・失敗も VoiceOver で通知する
        AccessibilityNotification.Announcement(message).post()
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

// MARK: - Save panel abstraction

/// NSSavePanel の生成・表示を抽象化する。テストで差し替え可能にする。
protocol SavePanelPresenting {
    func presentSavePanel(defaultFileName: String, allowedContentTypes: [UTType], initialDirectoryURL: URL?) -> URL?
}

struct NSSavePanelPresenter: SavePanelPresenting {
    func presentSavePanel(defaultFileName: String, allowedContentTypes: [UTType], initialDirectoryURL: URL?) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFileName
        panel.allowedContentTypes = allowedContentTypes
        panel.directoryURL = initialDirectoryURL
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }
}
