import Foundation

enum MediaKind: String, Codable, CaseIterable {
    case audio
    case video
}

enum MediaSortMode: String, CaseIterable, Identifiable {
    case natural = "Số tập / Tự nhiên"
    case name = "Tên A → Z"
    case dateDesc = "Mới thêm nhất"
    case duration = "Thời lượng"
    case size = "Dung lượng"

    var id: String { rawValue }
}

enum MediaFilter: String, CaseIterable, Identifiable {
    case all = "Tất cả"
    case audio = "Audio"
    case video = "Video"
    case unfinished = "Chưa xong"

    var id: String { rawValue }
}

enum BatchRenameStyle: String, CaseIterable, Identifiable {
    case normalizeEpisode = "Chuẩn hóa số tập (giữ tên gốc)"
    case compactNumbered = "Gọn: 04 - Tên truyện"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .normalizeEpisode:
            return "Ví dụ: (Tập 6 Q2) → (Tập 06 Q2), bỏ đuôi (MP3_70K) tùy chọn"
        case .compactNumbered:
            return "Đánh số 04, 05, 06... ở đầu và rút gọn phần lặp lại"
        }
    }
}

struct MediaItem: Identifiable, Codable, Hashable {
    var id: String
    var relativePath: String?
    var bookmarkData: Data?
    var remoteStreamURL: String? = nil
    var fileName: String
    var folderName: String
    var kind: MediaKind
    var sizeBytes: Int64
    var modifiedAt: TimeInterval
    var durationSec: Double
    var title: String?
    var artist: String?
    var album: String?
    var positionSec: Double
    var isCompleted: Bool
    var isFavorite: Bool
    var lastPlayedAt: TimeInterval

    var displayBaseName: String {
        (fileName as NSString).deletingPathExtension
    }

    func displayTitle(preferFileName: Bool) -> String {
        if preferFileName { return displayBaseName }
        if let t = title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t
        }
        return displayBaseName
    }

    var progressFraction: Double {
        guard durationSec > 0 else { return 0 }
        return min(max(positionSec / durationSec, 0), 1)
    }
}

struct FolderSource: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var isSandboxBuiltIn: Bool
    var bookmarkData: Data?
    var isEnabled: Bool
}

struct Playlist: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var createdAt: TimeInterval
    var itemIDs: [String]
}

struct RenamePreviewRow: Identifiable {
    var id: String { item.id }
    var item: MediaItem
    var newFileName: String
    var isSelected: Bool = true

    var hasChanges: Bool {
        item.fileName != newFileName
    }
}
