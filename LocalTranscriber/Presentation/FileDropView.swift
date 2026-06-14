import SwiftUI

struct FileDropView: View {
    let supportedExtensions: [String]
    let selectedFile: AudioFileInfo?
    let onFileSelected: (URL) -> Void

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
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .accessibilityLabel(selectedFile?.fileName ?? "音声ファイルのドロップゾーン")
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = supportedExtensions.map {
            UTType(filenameExtension: $0) ?? .audio
        }

        if panel.runModal() == .OK, let url = panel.url {
            // #region agent log
            DebugSessionLogger.log(
                location: "FileDropView.swift:openFilePanel",
                message: "file panel selection",
                data: [
                    "url": url.path,
                    "lastPathComponent": url.lastPathComponent,
                    "pathExtension": url.pathExtension,
                ],
                hypothesisId: "D"
            )
            // #endregion
            onFileSelected(url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { url, error in
            guard let url else {
                if let error {
                    // #region agent log
                    DebugSessionLogger.log(
                        location: "FileDropView.swift:handleDrop",
                        message: "drop loadFileRepresentation failed",
                        data: ["error": error.localizedDescription],
                        hypothesisId: "C,D"
                    )
                    // #endregion
                    AppLogger.error("Drop import failed: \(error.localizedDescription)", logger: AppLogger.fileAccess)
                }
                return
            }

            // #region agent log
            DebugSessionLogger.log(
                location: "FileDropView.swift:handleDrop",
                message: "drop temp url received",
                data: [
                    "tempUrl": url.path,
                    "lastPathComponent": url.lastPathComponent,
                    "pathExtension": url.pathExtension,
                    "fileExists": String(FileManager.default.fileExists(atPath: url.path)),
                ],
                hypothesisId: "A,C"
            )
            // #endregion

            do {
                let importsRoot = AppDirectories.importsDirectory
                try FileManager.default.createDirectory(at: importsRoot, withIntermediateDirectories: true)
                let destination = importsRoot.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: url, to: destination)

                // #region agent log
                DebugSessionLogger.log(
                    location: "FileDropView.swift:handleDrop",
                    message: "drop copy succeeded",
                    data: ["destination": destination.path],
                    hypothesisId: "E"
                )
                // #endregion

                DispatchQueue.main.async {
                    onFileSelected(destination)
                }
            } catch {
                // #region agent log
                DebugSessionLogger.log(
                    location: "FileDropView.swift:handleDrop",
                    message: "drop copy failed, using temp url fallback",
                    data: [
                        "copyError": error.localizedDescription,
                        "tempUrl": url.path,
                        "tempExists": String(FileManager.default.fileExists(atPath: url.path)),
                    ],
                    hypothesisId: "C,E"
                )
                // #endregion
                AppLogger.error("Drop copy failed: \(error.localizedDescription)", logger: AppLogger.fileAccess)
                DispatchQueue.main.async {
                    onFileSelected(url)
                }
            }
        }

        return true
    }
}

import UniformTypeIdentifiers
