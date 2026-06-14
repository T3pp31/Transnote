import Foundation

struct ModelOption: Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String
    let whisperKitModelName: String
}

struct LanguageOption: Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var selectedModelID: String
    @Published var selectedLanguageID: String

    let models: [ModelOption]
    let languages: [LanguageOption]
    let supportedExtensions: [String]

    private let defaults = UserDefaults.standard
    private let modelKey = "selectedModelID"
    private let languageKey = "selectedLanguageID"

    private init() {
        let config = AppConfig.shared
        models = config.models
        languages = config.languages
        supportedExtensions = config.supportedExtensions

        let defaultModel = config.defaultModelID
        let defaultLanguage = config.defaultLanguageID

        selectedModelID = defaults.string(forKey: modelKey) ?? defaultModel
        selectedLanguageID = defaults.string(forKey: languageKey) ?? defaultLanguage

        if !models.contains(where: { $0.id == selectedModelID }) {
            selectedModelID = defaultModel
        }
        if !languages.contains(where: { $0.id == selectedLanguageID }) {
            selectedLanguageID = defaultLanguage
        }
    }

    var selectedModel: ModelOption? {
        models.first { $0.id == selectedModelID }
    }

    var selectedLanguage: LanguageOption? {
        languages.first { $0.id == selectedLanguageID }
    }

    func persist() {
        defaults.set(selectedModelID, forKey: modelKey)
        defaults.set(selectedLanguageID, forKey: languageKey)
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

    init(bundle: Bundle = .main) {
        let plistURL = bundle.url(forResource: "Defaults", withExtension: "plist")
            ?? bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Config/Defaults.plist")

        let data: [String: Any]
        if let loaded = NSDictionary(contentsOf: plistURL) as? [String: Any] {
            data = loaded
        } else {
            data = Self.fallbackData
        }

        supportedExtensions = data["SupportedAudioExtensions"] as? [String] ?? ["wav", "mp3", "m4a", "flac"]
        defaultModelID = data["DefaultModelID"] as? String ?? "base"
        defaultLanguageID = data["DefaultLanguage"] as? String ?? "auto"
        modelsDirectoryName = data["ModelsDirectoryName"] as? String ?? "Models"

        models = Self.parseModels(from: data["Models"] as? [[String: Any]] ?? [])
        languages = Self.parseLanguages(from: data["Languages"] as? [[String: Any]] ?? [])
    }

    private static let fallbackData: [String: Any] = [
        "SupportedAudioExtensions": ["wav", "mp3", "m4a", "flac"],
        "DefaultModelID": "base",
        "DefaultLanguage": "auto",
        "ModelsDirectoryName": "Models"
    ]

    private static func parseModels(from raw: [[String: Any]]) -> [ModelOption] {
        raw.compactMap { item in
            guard let id = item["id"] as? String,
                  let displayName = item["displayName"] as? String,
                  let whisperKitModelName = item["whisperKitModelName"] as? String else {
                return nil
            }
            return ModelOption(id: id, displayName: displayName, whisperKitModelName: whisperKitModelName)
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
