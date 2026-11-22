import Foundation

struct Transcript: Codable, Identifiable, Sendable {
    /// JSON エクスポートのスキーマバージョン。
    /// 将来のフィールド追加時はインクリメントする。
    static let currentSchemaVersion = 1

    let id: UUID
    let sourceFileName: String
    let language: String?
    let createdAt: Date
    var fullText: String
    var segments: [TranscriptSegment]
    /// 文字起こしに使用したモデル ID（モデル設定の `id`）。
    var modelID: String?
    /// 元音声ファイルの識別用フィンガープリント（SHA256）。
    var sourceFileFingerprint: String?
    /// 最後に編集された日時（未編集なら nil）。
    var updatedAt: Date?
    let schemaVersion: Int

    init(
        id: UUID = UUID(),
        sourceFileName: String,
        language: String? = nil,
        createdAt: Date = Date(),
        fullText: String = "",
        segments: [TranscriptSegment] = [],
        modelID: String? = nil,
        sourceFileFingerprint: String? = nil,
        updatedAt: Date? = nil,
        schemaVersion: Int = Transcript.currentSchemaVersion
    ) {
        self.id = id
        self.sourceFileName = sourceFileName
        self.language = language
        self.createdAt = createdAt
        self.fullText = fullText
        self.segments = segments
        self.modelID = modelID
        self.sourceFileFingerprint = sourceFileFingerprint
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
    }

    // 既存 JSON（schemaVersion なし）も読み込めるよう decodeIfPresent を使う。
    private enum CodingKeys: String, CodingKey {
        case id, sourceFileName, language, createdAt, fullText, segments, modelID, sourceFileFingerprint, updatedAt, schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceFileName = try container.decode(String.self, forKey: .sourceFileName)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        fullText = try container.decode(String.self, forKey: .fullText)
        segments = try container.decode([TranscriptSegment].self, forKey: .segments)
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        sourceFileFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceFileFingerprint)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        let rawSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        guard rawSchemaVersion >= 1, rawSchemaVersion <= Self.currentSchemaVersion else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "Unsupported schemaVersion: \(rawSchemaVersion)"
                )
            )
        }
        schemaVersion = rawSchemaVersion
    }

    /// Full Text の編集内容を `fullText` と `segments` の両方に同期する。
    /// タイムスタンプとセグメント ID を保持したまま、TXT と SRT/VTT/Markdown の食い違いを防ぐ。
    mutating func applyFullTextEdit(_ newText: String) {
        fullText = newText
        guard !segments.isEmpty else { return }
        if segments.count == 1 {
            segments[0].text = newText
            return
        }

        let normalized = newText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalized.isEmpty {
            for index in segments.indices {
                segments[index].text = ""
            }
            return
        }

        let lines = normalized.components(separatedBy: "\n")
        if lines.count > 1 {
            syncMultilineText(lines)
        } else {
            syncSingleLineText(normalized)
        }
    }

    private mutating func syncMultilineText(_ lines: [String]) {
        let oldTexts = segments.map(\.text)
        let oldCount = oldTexts.count
        let newCount = lines.count

        if newCount == oldCount {
            for index in 0..<oldCount {
                segments[index].text = lines[index]
            }
            return
        }

        // 変更されていない前後行をアンカーし、編集された中央区間のみを更新する。
        var prefix = 0
        while prefix < oldCount && prefix < newCount && oldTexts[prefix] == lines[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < (oldCount - prefix) && suffix < (newCount - prefix)
            && oldTexts[oldCount - 1 - suffix] == lines[newCount - 1 - suffix] {
            suffix += 1
        }

        let oldMidStart = prefix
        let oldMidEnd = oldCount - suffix
        let newMidStart = prefix
        let newMidEnd = newCount - suffix
        let oldMidCount = oldMidEnd - oldMidStart
        let newMidCount = newMidEnd - newMidStart

        if oldMidCount == 0 {
            let inserted = lines[newMidStart..<newMidEnd].joined(separator: "\n")
            if prefix > 0 {
                let existing = segments[prefix - 1].text
                segments[prefix - 1].text = existing.isEmpty ? inserted : "\(existing)\n\(inserted)"
            } else {
                let existing = segments[0].text
                segments[0].text = existing.isEmpty ? inserted : "\(inserted)\n\(existing)"
            }
            return
        }

        if newMidCount == 0 {
            for index in oldMidStart..<oldMidEnd {
                segments[index].text = ""
            }
            return
        }

        if newMidCount >= oldMidCount {
            for offset in 0..<(oldMidCount - 1) {
                segments[oldMidStart + offset].text = lines[newMidStart + offset]
            }
            let remainingStart = newMidStart + oldMidCount - 1
            segments[oldMidEnd - 1].text = lines[remainingStart..<newMidEnd].joined(separator: "\n")
        } else {
            for offset in 0..<newMidCount {
                segments[oldMidStart + offset].text = lines[newMidStart + offset]
            }
            for index in (oldMidStart + newMidCount)..<oldMidEnd {
                segments[index].text = ""
            }
        }
    }

    private mutating func syncSingleLineText(_ text: String) {
        let characters = Array(text)
        let textWeights = segments.map { Double($0.text.count) }
        let useTextWeights = textWeights.contains { $0 > 0 }
        let weights: [Double] = useTextWeights
            ? textWeights.map { max($0, 1.0) }
            : segments.map { max($0.endTime - $0.startTime, 0.001) }
        let totalWeight = weights.reduce(0, +)

        var cursor = 0
        var cumulativeWeight = 0.0
        for index in segments.indices {
            if index == segments.count - 1 {
                let slice = cursor < characters.count ? String(characters[cursor...]) : ""
                segments[index].text = slice.trimmingCharacters(in: .whitespaces)
                break
            }

            cumulativeWeight += weights[index]
            let ideal = min(
                characters.count,
                max(cursor, Int((Double(characters.count) * cumulativeWeight / totalWeight).rounded()))
            )
            let splitIndex = nearestWhitespaceBoundary(
                in: characters,
                around: ideal,
                minIndex: cursor,
                maxIndex: characters.count
            ) ?? ideal

            let slice = splitIndex > cursor ? String(characters[cursor..<splitIndex]) : ""
            segments[index].text = slice.trimmingCharacters(in: .whitespaces)
            cursor = splitIndex
            while cursor < characters.count && characters[cursor].isWhitespace {
                cursor += 1
            }
        }
    }

    private func nearestWhitespaceBoundary(
        in characters: [Character],
        around target: Int,
        minIndex: Int,
        maxIndex: Int
    ) -> Int? {
        guard target > minIndex, target < maxIndex else { return nil }
        let maxRadius = min(8, max(1, (maxIndex - minIndex) / 4))
        for distance in 0...maxRadius {
            let right = target + distance
            if right < maxIndex && characters[right].isWhitespace {
                return right
            }
            let left = target - distance
            if distance > 0 && left > minIndex && characters[left].isWhitespace {
                return left
            }
        }
        return nil
    }
}
