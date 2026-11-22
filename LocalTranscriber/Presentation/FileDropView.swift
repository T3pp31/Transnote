import SwiftUI
import UniformTypeIdentifiers

/// ドロップ取込と「ファイルを開く」パネル選択の競合を世代トークンで調停する。
@MainActor
final class FileDropCoordinator: ObservableObject {
    @Published var dropErrorMessage: String?
    @Published private(set) var isImportingDrop = false
    private(set) var dropGeneration = 0

    func beginDrop() -> Int {
        dropErrorMessage = nil
        dropGeneration += 1
        isImportingDrop = true
        return dropGeneration
    }

    /// 進行中のドロップ取込を無効化し、以後のドロップをブロックしないよう状態を解除する。
    func invalidateInFlightDrop() {
        dropGeneration += 1
        isImportingDrop = false
        dropErrorMessage = nil
    }

    func selectFileFromPanel(url: URL, onFileSelected: (URL, String?) -> Void) {
        invalidateInFlightDrop()
        onFileSelected(url, nil)
    }

    func completeDrop(
        generation: Int,
        isBusy: Bool,
        orphanImportedURL: URL? = nil,
        cleanupOrphan: (URL) -> Void = { try? FileManager.default.removeItem(at: $0) },
        update: () -> Void
    ) {
        guard generation == dropGeneration else {
            // 新しい選択や後続ドロップにより無効化された古い完了は反映せず、不要コピーだけ片付ける。
            if let orphanImportedURL {
                cleanupOrphan(orphanImportedURL)
            }
            return
        }

        isImportingDrop = false
        guard !isBusy else {
            if let orphanImportedURL {
                cleanupOrphan(orphanImportedURL)
            }
            return
        }

        update()
    }
}

struct FileDropView: View {
    let supportedExtensions: [String]
    let selectedFile: AudioFileInfo?
    let onFileSelected: (URL, String?) -> Void
    let audioImportService: AudioImportService
    var isBusy: Bool = false
    var externalSelectionGeneration: Int = 0

    @State private var isTargeted = false
    @State private var isHovered = false
    @StateObject private var coordinator = FileDropCoordinator()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let cornerRadius: CGFloat = DesignTokens.Corner.card

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.controlSpacing) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: DesignTokens.Icon.hero))
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

            Button("ファイルを開く…") {
                openFilePanel()
            }
            .disabled(isBusy)
            .keyboardShortcut("o", modifiers: [.command])
            .help("音声ファイルを開く（⌘O）")
            .accessibilityLabel("音声ファイルを開く")
            .accessibilityHint("ファイルを開くダイアログを開きます")

            if let dropErrorMessage = coordinator.dropErrorMessage {
                HStack(spacing: DesignTokens.Spacing.compactSpacing) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignTokens.Colors.warning)
                    Text(dropErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.warning)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Button {
                        coordinator.dropErrorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignTokens.Colors.warning.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("エラーを閉じる")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(
            minHeight: DesignTokens.Layout.dropZoneMinHeight,
            maxHeight: DesignTokens.Layout.dropZoneMaxHeight
        )
        .padding(24)
        .background(dropZoneSurface)
        .onHover { hovering in
            isHovered = hovering
        }
        .onChange(of: externalSelectionGeneration) { _ in
            coordinator.invalidateInFlightDrop()
        }
        .onChange(of: isBusy) { busy in
            if busy {
                coordinator.invalidateInFlightDrop()
            }
        }
        .onDrop(of: acceptedDropTypes, isTargeted: $isTargeted) { providers in
            guard !isBusy, !coordinator.isImportingDrop else { return false }
            return handleDrop(providers: providers)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(dropZoneAccessibilityLabel)
        .accessibilityHint(dropZoneAccessibilityHint)
    }

    private var supportedFormatsDescription: String {
        supportedExtensions.map { $0.uppercased() }.joined(separator: ", ")
    }

    private var dropZoneAccessibilityLabel: String {
        if let selectedFile {
            return "選択中の音声ファイル、\(selectedFile.fileName)"
        }
        return "音声ファイルのドロップゾーン"
    }

    private var dropZoneAccessibilityHint: String {
        if selectedFile != nil {
            return "別の音声ファイルをドロップまたはファイルを開くで差し替えできます"
        }
        return "対応形式は \(supportedFormatsDescription) です。音声ファイルをドロップするか、ファイルを開いてください"
    }

    private var dropZoneSurface: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(reduceTransparency ? AnyShapeStyle(DesignTokens.Colors.opaqueSurface) : AnyShapeStyle(.regularMaterial))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(dropAccentFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(dropBorderColor, lineWidth: 1)
            }
            .shadow(
                color: dropShadowColor,
                radius: isTargeted ? 12 : (isHovered ? 8 : 4),
                y: isTargeted ? 4 : 2
            )
    }

    private var dropAccentFill: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.08)
        }
        if isHovered {
            return DesignTokens.Colors.hoverFill(colorScheme)
        }
        return Color(NSColor.controlBackgroundColor).opacity(0.5)
    }

    private var dropBorderColor: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.45)
        }
        return DesignTokens.Colors.border(colorScheme)
    }

    private var dropShadowColor: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.18)
        }
        return DesignTokens.Colors.dropShadow(colorScheme, isHovered: isHovered)
    }

    private func openFilePanel() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = contentTypesForPicker()

        if panel.runModal() == .OK, let url = panel.url {
            coordinator.selectFileFromPanel(url: url, onFileSelected: onFileSelected)
        }
    }

    private var acceptedDropTypes: [UTType] {
        var types: [UTType] = [.fileURL, .audio]
        types.append(contentsOf: SupportedAudioTypes.allowedContentTypes(for: supportedExtensions))
        return Array(Set(types))
    }

    private func contentTypesForPicker() -> [UTType] {
        SupportedAudioTypes.allowedContentTypes(for: supportedExtensions)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        coordinator.dropErrorMessage = nil

        // 複数ファイルのドロップは正式対応しない（現状は1ファイルのみ）。
        // 明示的に拒否して、ユーザーが期待する挙動を明確にする。
        if providers.count > 1 {
            coordinator.dropErrorMessage = NSLocalizedString(
                "複数ファイルのドロップには対応していません。1つの音声ファイルをドロップしてください。",
                comment: "Multiple file drop unsupported"
            )
            return false
        }

        guard let provider = providers.first else { return false }
        let generation = coordinator.beginDrop()

        let suggestedName = provider.suggestedName
        let typeIdentifiers = DropImportService.preferredTypeIdentifiers(from: provider)

        loadDropItem(
            provider: provider,
            typeIdentifiers: typeIdentifiers,
            index: 0,
            suggestedName: suggestedName,
            generation: generation
        )
        return true
    }

    private func loadDropItem(
        provider: NSItemProvider,
        typeIdentifiers: [String],
        index: Int,
        suggestedName: String?,
        generation: Int
    ) {
        guard index < typeIdentifiers.count else {
            AppLogger.error("Drop import failed: unsupported dropped item", logger: AppLogger.fileAccess)
            finishDrop(generation: generation) {
                coordinator.dropErrorMessage = NSLocalizedString(
                    "対応している音声ファイルを読み込めませんでした。",
                    comment: "Drop import failed for unsupported item"
                )
            }
            return
        }

        let typeIdentifier = typeIdentifiers[index]

        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { tempURL, error in
            guard let tempURL else {
                self.loadDropItem(
                    provider: provider,
                    typeIdentifiers: typeIdentifiers,
                    index: index + 1,
                    suggestedName: suggestedName,
                    generation: generation
                )
                return
            }

            self.importDroppedRepresentation(
                tempURL: tempURL,
                suggestedName: suggestedName,
                typeIdentifiers: typeIdentifiers,
                generation: generation
            )
        }
    }

    private func finishDrop(
        generation: Int,
        orphanImportedURL: URL? = nil,
        update: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            coordinator.completeDrop(
                generation: generation,
                isBusy: isBusy,
                orphanImportedURL: orphanImportedURL,
                update: update
            )
        }
    }

    private func importDroppedRepresentation(
        tempURL: URL,
        suggestedName: String?,
        typeIdentifiers: [String],
        generation: Int
    ) {
        let fileName = DropImportService.resolvedFileName(
            sourceURL: tempURL,
            suggestedName: suggestedName,
            typeIdentifiers: typeIdentifiers
        )

        guard DropImportService.hasSupportedExtension(fileName, supportedExtensions: supportedExtensions) else {
            AppLogger.error("Drop import failed: unsupported extension for \(fileName)", logger: AppLogger.fileAccess)
            finishDrop(generation: generation) {
                coordinator.dropErrorMessage = ErrorMapper.userMessage(for: AppError.unsupportedFileExtension(fileName))
            }
            return
        }

        do {
            let importedURL = try audioImportService.importFile(
                from: tempURL,
                preferredFileName: fileName
            )
            let createdCopy = importedURL.standardizedFileURL != tempURL.standardizedFileURL
                ? importedURL
                : nil
            finishDrop(generation: generation, orphanImportedURL: createdCopy) {
                coordinator.dropErrorMessage = nil
                onFileSelected(importedURL, nil)
            }
        } catch {
            AppLogger.error("Drop import failed: \(error.localizedDescription)", logger: AppLogger.fileAccess)
            finishDrop(generation: generation) {
                coordinator.dropErrorMessage = ErrorMapper.userMessage(for: error)
            }
        }
    }
}
