import SwiftUI

struct FileDropView: View {
    let supportedExtensions: [String]
    let selectedFile: AudioFileInfo?
    let onFileSelected: (URL, String?) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            if let selectedFile {
                Text(selectedFile.fileName)
                    .font(.headline)
                Text("\(selectedFile.fileExtension.uppercased()) · \(selectedFile.formattedFileSize)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("音声ファイルをここにドロップ")
                    .font(.headline)
                Text("対応形式: \(supportedExtensions.map { $0.uppercased() }.joined(separator: ", "))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("ファイルを選択…") {
                openFilePanel()
            }
            .keyboardShortcut("o", modifiers: [.command])
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
        )
        .onDrop(of: acceptedDropTypes, isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .accessibilityLabel(selectedFile?.fileName ?? "音声ファイルのドロップゾーン")
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = contentTypesForPicker()

        if panel.runModal() == .OK, let url = panel.url {
            onFileSelected(url, nil)
        }
    }

    private var acceptedDropTypes: [UTType] {
        var types: [UTType] = [.fileURL, .audio]
        for ext in supportedExtensions {
            switch ext.lowercased() {
            case "m4a":
                types.append(.mpeg4Audio)
            case "mp3":
                types.append(.mp3)
            case "wav":
                types.append(.wav)
            case "flac":
                if let flac = UTType(filenameExtension: "flac") {
                    types.append(flac)
                }
            default:
                if let type = UTType(filenameExtension: ext) {
                    types.append(type)
                }
            }
        }
        return Array(Set(types))
    }

    private func contentTypesForPicker() -> [UTType] {
        supportedExtensions.compactMap { ext in
            switch ext.lowercased() {
            case "m4a":
                return .mpeg4Audio
            case "mp3":
                return .mp3
            case "wav":
                return .wav
            case "flac":
                return UTType(filenameExtension: "flac") ?? .audio
            default:
                return UTType(filenameExtension: ext)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        let suggestedName = provider.suggestedName
        let typeIdentifiers = DropImportService.preferredTypeIdentifiers(from: provider)

        loadDropItem(
            provider: provider,
            typeIdentifiers: typeIdentifiers,
            index: 0,
            suggestedName: suggestedName
        )
        return true
    }

    private func loadDropItem(
        provider: NSItemProvider,
        typeIdentifiers: [String],
        index: Int,
        suggestedName: String?
    ) {
        guard index < typeIdentifiers.count else {
            AppLogger.error("Drop import failed: unsupported dropped item", logger: AppLogger.fileAccess)
            return
        }

        let typeIdentifier = typeIdentifiers[index]

        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { tempURL, error in
            guard let tempURL else {
                self.loadDropItem(
                    provider: provider,
                    typeIdentifiers: typeIdentifiers,
                    index: index + 1,
                    suggestedName: suggestedName
                )
                return
            }

            self.importDroppedRepresentation(
                tempURL: tempURL,
                suggestedName: suggestedName,
                typeIdentifiers: typeIdentifiers
            )
        }
    }

    private func importDroppedRepresentation(
        tempURL: URL,
        suggestedName: String?,
        typeIdentifiers: [String]
    ) {
        let fileName = DropImportService.resolvedFileName(
            sourceURL: tempURL,
            suggestedName: suggestedName,
            typeIdentifiers: typeIdentifiers
        )

        guard DropImportService.hasSupportedExtension(fileName, supportedExtensions: supportedExtensions) else {
            AppLogger.error("Drop import failed: unsupported extension for \(fileName)", logger: AppLogger.fileAccess)
            return
        }

        do {
            let importedURL = try AudioImportService().importFile(
                from: tempURL,
                preferredFileName: fileName
            )
            DispatchQueue.main.async {
                self.onFileSelected(importedURL, nil)
            }
        } catch {
            AppLogger.error("Drop import failed: \(error.localizedDescription)", logger: AppLogger.fileAccess)
        }
    }
}

import UniformTypeIdentifiers
