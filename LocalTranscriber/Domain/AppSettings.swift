import Foundation

struct ModelOption: Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String
    let whisperKitModelName: String

    /// ダウンロードサイズ（バイト）。未設定の場合は nil。
    let downloadSizeBytes: Int64?
    let license: String?
    let distributionSource: String?
    let modelVersion: String?

    init(
        id: String,
        displayName: String,
        whisperKitModelName: String,
        downloadSizeBytes: Int64? = nil,
        license: String? = nil,
        distributionSource: String? = nil,
        modelVersion: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.whisperKitModelName = whisperKitModelName
        self.downloadSizeBytes = downloadSizeBytes
        self.license = license
        self.distributionSource = distributionSource
        self.modelVersion = modelVersion
    }

    /// Localizable.xcstrings から取得するローカライズ済み表示名。
    var localizedDisplayName: String {
        NSLocalizedString("model.\(id)", comment: "Model display name")
    }
}

struct LanguageOption: Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String

    /// Localizable.xcstrings から取得するローカライズ済み表示名。
    var localizedDisplayName: String {
        NSLocalizedString("language.\(id)", comment: "Language display name")
    }
}

/// ViewModel から参照・変更するアプリ設定の抽象。テスト・DI に用いる。
/// 永続化対象の設定値と、その解決に必要な選択肢を公開する。
/// 推奨モデルなど設定画面向けの派生情報は具象 AppSettings で提供する。
@MainActor
protocol AppSettingsProviding: AnyObject, ObservableObject {
    var selectedModelID: String { get set }
    var selectedLanguageID: String { get set }
    var updateCheckEnabled: Bool { get set }
    var defaultExportFormat: ExportFormat { get set }
    var models: [ModelOption] { get }
    var languages: [LanguageOption] { get }
    var supportedExtensions: [String] { get }
    var selectedModel: ModelOption? { get }
    var selectedLanguage: LanguageOption? { get }
    var vadEnabled: Bool { get set }
    func persist()
}

@MainActor
final class AppSettings: ObservableObject, AppSettingsProviding {
    static let shared = AppSettings()

    @Published var selectedModelID: String
    @Published var selectedLanguageID: String
    @Published var updateCheckEnabled: Bool
    @Published var defaultExportFormat: ExportFormat
    @Published var vadEnabled: Bool

    let models: [ModelOption]
    let languages: [LanguageOption]
    let supportedExtensions: [String]

    private let defaults: UserDefaults
    private let defaultModelID: String
    private let physicalMemoryGBProvider: () -> Double
    private let processorCountProvider: () -> Int
    private let modelKey = "selectedModelID"
    private let languageKey = "selectedLanguageID"
    private let updateCheckKey = "updateCheckEnabled"
    private let defaultExportFormatKey = "defaultExportFormat"
    private let vadKey = "vadEnabled"

    init(
        config: AppConfig = .shared,
        defaults: UserDefaults = .standard,
        physicalMemoryGBProvider: @escaping () -> Double = {
            Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        },
        processorCountProvider: @escaping () -> Int = {
            ProcessInfo.processInfo.processorCount
        }
    ) {
        self.defaults = defaults
        defaultModelID = config.defaultModelID
        self.physicalMemoryGBProvider = physicalMemoryGBProvider
        self.processorCountProvider = processorCountProvider
        models = config.models
        languages = config.languages
        supportedExtensions = config.supportedExtensions

        let defaultModel = config.defaultModelID
        let defaultLanguage = config.defaultLanguageID

        selectedModelID = defaults.string(forKey: modelKey) ?? defaultModel
        selectedLanguageID = defaults.string(forKey: languageKey) ?? defaultLanguage
        updateCheckEnabled = defaults.object(forKey: updateCheckKey) as? Bool ?? config.updateCheckEnabled
        if let raw = defaults.string(forKey: defaultExportFormatKey),
           let format = ExportFormat(rawValue: raw) {
            defaultExportFormat = format
        } else {
            defaultExportFormat = .txt
        }
        vadEnabled = defaults.object(forKey: vadKey) as? Bool ?? false

        // 既定 ID も一覧に存在しない場合は、利用可能な先頭の選択肢へ戻す。
        if !models.contains(where: { $0.id == selectedModelID }) {
            selectedModelID = models.first(where: { $0.id == defaultModel })?.id
                ?? models.first?.id
                ?? defaultModel
        }
        if !languages.contains(where: { $0.id == selectedLanguageID }) {
            selectedLanguageID = languages.first(where: { $0.id == defaultLanguage })?.id
                ?? languages.first?.id
                ?? defaultLanguage
        }
    }

    var selectedModel: ModelOption? {
        models.first { $0.id == selectedModelID }
    }

    /// RAM・CPUコア数に基づく推奨モデル ID。
    /// - 16GB 以上または 12 コア以上: small
    /// - 8GB 以上: base
    /// - それ以外: tiny
    var recommendedModelID: String {
        Self.recommendedModelID(
            memoryGB: physicalMemoryGBProvider(),
            processorCount: processorCountProvider()
        )
    }

    nonisolated static func recommendedModelID(memoryGB: Double, processorCount: Int) -> String {
        if memoryGB >= 16 || processorCount >= 12 {
            return "small"
        }
        if memoryGB >= 8 {
            return "base"
        }
        return "tiny"
    }

    var recommendedModel: ModelOption? {
        // モデル構成が変わって推奨IDが存在しない場合は既定モデルへフォールバックする。
        models.first { $0.id == recommendedModelID }
            ?? models.first { $0.id == defaultModelID }
            ?? models.first
    }

    var selectedLanguage: LanguageOption? {
        languages.first { $0.id == selectedLanguageID }
    }

    func persist() {
        defaults.set(selectedModelID, forKey: modelKey)
        defaults.set(selectedLanguageID, forKey: languageKey)
        defaults.set(updateCheckEnabled, forKey: updateCheckKey)
        defaults.set(defaultExportFormat.rawValue, forKey: defaultExportFormatKey)
        defaults.set(vadEnabled, forKey: vadKey)
    }
}

struct AppConfig {
    static let shared = AppConfig()

    let supportedExtensions: [String]
    let defaultModelID: String
    let defaultLanguageID: String
    let modelsDirectoryName: String
    let models: [ModelOption]
    let languages: [LanguageOption]
    let updateCheckEnabled: Bool
    let expectedGitHubRepository: String
    let githubReleasesAPIURL: URL
    let updateDownloadFallbackURL: URL
    let updateDMGAssetName: String
    let allowedUpdateDownloadHosts: [String]
    let historySearchDebounceNanoseconds: UInt64
    let maxImportFileSizeBytes: Int64

    private static let placeholderURL = URL(string: "about:blank")!

    /// 設定不整合を起動時に明示的に検出するための検証結果。
    /// 空でない場合は LocalTranscriberApp の起動時にログへ出力する。
    var validationErrors: [String] {
        var errors: [String] = []
        if defaultModelID.isEmpty {
            errors.append("defaultModelID is empty")
        } else if !models.contains(where: { $0.id == defaultModelID }) {
            errors.append("defaultModelID '\(defaultModelID)' is not present in Models")
        }
        if defaultLanguageID.isEmpty {
            errors.append("defaultLanguageID is empty")
        } else if !languages.contains(where: { $0.id == defaultLanguageID }) {
            errors.append("defaultLanguageID '\(defaultLanguageID)' is not present in Languages")
        }
        if supportedExtensions.isEmpty {
            errors.append("supportedExtensions is empty")
        }
        if updateCheckEnabled {
            if expectedGitHubRepository.isEmpty {
                errors.append("expectedGitHubRepository is empty")
            }
            if githubReleasesAPIURL == Self.placeholderURL {
                errors.append("githubReleasesAPIURL is missing or invalid")
            }
            if updateDownloadFallbackURL == Self.placeholderURL {
                errors.append("updateDownloadFallbackURL is missing or invalid")
            }
            if updateDMGAssetName.isEmpty {
                errors.append("updateDMGAssetName is empty")
            }
            if allowedUpdateDownloadHosts.isEmpty {
                errors.append("allowedUpdateDownloadHosts is empty")
            }
        }
        return errors
    }

    init(bundle: Bundle = .main) {
        self.init(dictionary: Self.loadDefaultsDictionary(from: bundle))
    }

    /// Defaults.plist の内容を正本として構成する。
    /// モデル・言語・URL などの二重定義を避けるため、欠損時はハードコード代替を持たず
    /// 安全側の空値にし、`validationErrors` で設定不備を検出できるようにする。
    init(dictionary data: [String: Any]) {
        supportedExtensions = data["SupportedAudioExtensions"] as? [String] ?? []
        defaultModelID = data["DefaultModelID"] as? String ?? ""
        defaultLanguageID = data["DefaultLanguage"] as? String ?? ""
        modelsDirectoryName = data["ModelsDirectoryName"] as? String ?? "Models"

        models = Self.parseModels(from: data["Models"] as? [[String: Any]] ?? [])
        languages = Self.parseLanguages(from: data["Languages"] as? [[String: Any]] ?? [])

        updateCheckEnabled = data["UpdateCheckEnabled"] as? Bool ?? false
        expectedGitHubRepository = data["ExpectedGitHubRepository"] as? String ?? ""
        githubReleasesAPIURL = Self.url(from: data["GitHubReleasesAPIURL"] as? String)
        updateDownloadFallbackURL = Self.url(from: data["UpdateDownloadFallbackURL"] as? String)
        updateDMGAssetName = data["UpdateDMGAssetName"] as? String ?? ""
        allowedUpdateDownloadHosts = data["AllowedUpdateDownloadHosts"] as? [String] ?? []
        historySearchDebounceNanoseconds = UInt64(max(0, Self.int64(from: data["HistorySearchDebounceNanoseconds"], fallback: 0)))
        maxImportFileSizeBytes = Self.int64(from: data["MaxImportFileSizeBytes"], fallback: 0)
    }

    private static func loadDefaultsDictionary(from bundle: Bundle) -> [String: Any] {
        if let bundledURL = bundle.url(forResource: "Defaults", withExtension: "plist"),
           let loaded = NSDictionary(contentsOf: bundledURL) as? [String: Any] {
            return loaded
        }
        // Bundle.main がテストランナー等を指す場合でも、アプリバンドル同梱の Defaults.plist を正本として参照する。
        if bundle == .main {
            let appBundle = Bundle(for: AppSettings.self)
            if let appBundledURL = appBundle.url(forResource: "Defaults", withExtension: "plist"),
               let loaded = NSDictionary(contentsOf: appBundledURL) as? [String: Any] {
                return loaded
            }
        }
        #if DEBUG
        // #filePath: .../Transnote/LocalTranscriber/Domain/AppSettings.swift
        let developmentPlistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Config/Defaults.plist")
        if let loaded = NSDictionary(contentsOf: developmentPlistURL) as? [String: Any] {
            return loaded
        }
        #endif
        return [:]
    }

    init(
        supportedExtensions: [String],
        defaultModelID: String,
        defaultLanguageID: String,
        modelsDirectoryName: String,
        models: [ModelOption],
        languages: [LanguageOption],
        updateCheckEnabled: Bool,
        expectedGitHubRepository: String = AppConfig.shared.expectedGitHubRepository,
        githubReleasesAPIURL: URL,
        updateDownloadFallbackURL: URL,
        updateDMGAssetName: String,
        allowedUpdateDownloadHosts: [String] = AppConfig.shared.allowedUpdateDownloadHosts,
        maxImportFileSizeBytes: Int64 = AppConfig.shared.maxImportFileSizeBytes,
        historySearchDebounceNanoseconds: UInt64 = 0
    ) {
        self.supportedExtensions = supportedExtensions
        self.defaultModelID = defaultModelID
        self.defaultLanguageID = defaultLanguageID
        self.modelsDirectoryName = modelsDirectoryName
        self.models = models
        self.languages = languages
        self.updateCheckEnabled = updateCheckEnabled
        self.expectedGitHubRepository = expectedGitHubRepository
        self.githubReleasesAPIURL = githubReleasesAPIURL
        self.updateDownloadFallbackURL = updateDownloadFallbackURL
        self.updateDMGAssetName = updateDMGAssetName
        self.allowedUpdateDownloadHosts = allowedUpdateDownloadHosts
        self.maxImportFileSizeBytes = maxImportFileSizeBytes
        self.historySearchDebounceNanoseconds = historySearchDebounceNanoseconds
    }

    private static func int64(from value: Any?, fallback: Int64) -> Int64 {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        return fallback
    }

    private static func url(from string: String?) -> URL {
        if let string, !string.isEmpty, let url = URL(string: string) {
            return url
        }
        return placeholderURL
    }

    private static func parseModels(from raw: [[String: Any]]) -> [ModelOption] {
        raw.compactMap { item in
            guard let id = item["id"] as? String,
                  let displayName = item["displayName"] as? String,
                  let whisperKitModelName = item["whisperKitModelName"] as? String else {
                return nil
            }
            let size = (item["downloadSizeBytes"] as? NSNumber)?.int64Value
            let license = item["license"] as? String
            let source = item["distributionSource"] as? String
            let version = item["modelVersion"] as? String
            return ModelOption(
                id: id,
                displayName: displayName,
                whisperKitModelName: whisperKitModelName,
                downloadSizeBytes: size,
                license: license,
                distributionSource: source,
                modelVersion: version
            )
        }
    }

    private static func parseLanguages(from raw: [[String: Any]]) -> [LanguageOption] {
        raw.compactMap { item in
            guard let id = item["id"] as? String,
                  let displayName = item["displayName"] as? String else {
                return nil
            }
            return LanguageOption(id: id, displayName: displayName)
        }
    }
}
