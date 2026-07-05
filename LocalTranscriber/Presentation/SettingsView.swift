import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("設定")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("文字起こしモデル")
                        .font(.headline)
                    Picker("モデル", selection: $settings.selectedModelID) {
                        ForEach(settings.models) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 300)
                    .onChange(of: settings.selectedModelID) { _ in
                        settings.persist()
                    }
                    Text("使用するWhisperモデルを選択します。モデルは別途ダウンロードが必要です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("文字起こし言語")
                        .font(.headline)
                    Picker("言語", selection: $settings.selectedLanguageID) {
                        ForEach(settings.languages) { language in
                            Text(language.displayName).tag(language.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 300)
                    .onChange(of: settings.selectedLanguageID) { _ in
                        settings.persist()
                    }
                    Text("音声の言語を選択します。Autoは自動検出です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("閉じる") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 360)
    }
}
