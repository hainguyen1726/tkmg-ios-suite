import Foundation

enum EpisodeNameHelper {
    private static let noisePatterns: [String] = [
        #"\s*[\(\[]?\s*(MP3_70K|MP3_128K|MP3_320K|M4A_\d+K|Audio)\s*[\)\]]?"#,
        #"\s*\(\d{3,4}p\)"#
    ]

    static func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds > 0 else { return "00:00" }
        let total = Int(seconds)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func cleanNoise(_ text: String) -> String {
        var result = text
        for pattern in noisePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }
        return result.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedEpisodeFileName(
        originalFileName: String,
        style: BatchRenameStyle,
        stripQualitySuffix: Bool
    ) -> String {
        let ext = (originalFileName as NSString).pathExtension
        var base = (originalFileName as NSString).deletingPathExtension
        if stripQualitySuffix {
            base = cleanNoise(base)
        }

        // Pad "(Tập N)" or "Tập N" to 2 digits
        if let regex = try? NSRegularExpression(pattern: #"(Tập|Tap|Ep|Episode)\s*0*(\d+)"#, options: [.caseInsensitive]) {
            let ns = base as NSString
            let matches = regex.matches(in: base, range: NSRange(location: 0, length: ns.length))
            if let first = matches.first, first.numberOfRanges >= 3 {
                let numStr = ns.substring(with: first.range(at: 2))
                let padded = String(format: "%02d", Int(numStr) ?? 0)
                if style == .compactNumbered {
                    let stripped = regex.stringByReplacingMatches(
                        in: base,
                        range: NSRange(location: 0, length: ns.length),
                        withTemplate: ""
                    )
                    .trimmingCharacters(in: CharacterSet(charactersIn: " -_()[]"))
                    let finalBase = stripped.isEmpty ? padded : "\(padded) - \(stripped)"
                    return ext.isEmpty ? finalBase : "\(finalBase).\(ext)"
                } else {
                    let keyword = ns.substring(with: first.range(at: 1))
                    let rangeAll = first.range(at: 0)
                    base = ns.replacingCharacters(in: rangeAll, with: "\(keyword) \(padded)")
                }
            }
        }
        return ext.isEmpty ? base : "\(base).\(ext)"
    }
}
