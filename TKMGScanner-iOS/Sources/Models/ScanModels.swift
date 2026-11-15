import Foundation

enum ScanFilterMode: Int, Codable, CaseIterable, Identifiable {
    case original = 0
    case magicColor = 1
    case bwDoc = 2
    case grayscale = 3
    case superSharp = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .original: return "Gốc Scan"
        case .magicColor: return "Màu Sắc Nét"
        case .bwDoc: return "Đen Trắng"
        case .grayscale: return "Thang Xám"
        case .superSharp: return "Siêu Nét"
        }
    }

    var shortLabel: String {
        switch self {
        case .original: return "Gốc"
        case .magicColor: return "Magic"
        case .bwDoc: return "B&W"
        case .grayscale: return "Xám"
        case .superSharp: return "Siêu nét"
        }
    }
}

enum PdfPageSize: String, CaseIterable, Identifiable {
    case a4 = "Khổ chuẩn A4"
    case original = "Theo ảnh gốc"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .a4: return "Tự căn giữa vừa trang in A4 (595×842pt)"
        case .original: return "Giữ đúng tỷ lệ từng trang"
        }
    }
}

enum PdfQuality: String, CaseIterable, Identifiable {
    case high = "Nét cao (In ấn)"
    case standard = "Tiêu chuẩn (Cân bằng)"
    case compact = "Nhẹ (Gửi Zalo / Email)"

    var id: String { rawValue }

    var maxEdgePx: CGFloat {
        switch self {
        case .high: return 2200
        case .standard: return 1650
        case .compact: return 1200
        }
    }

    var jpegCompression: CGFloat {
        switch self {
        case .high: return 0.92
        case .standard: return 0.82
        case .compact: return 0.68
        }
    }
}

enum DocumentSortOrder: String, CaseIterable, Identifiable {
    case updatedDesc = "Mới cập nhật"
    case createdDesc = "Mới tạo"
    case titleAsc = "Tên A → Z"

    var id: String { rawValue }
}

enum ImageExportFormat: String, CaseIterable, Identifiable {
    case jpeg = "JPEG (Nhẹ, gửi nhanh)"
    case png = "PNG (Sắc nét không nén)"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        }
    }
}

enum DocumentExportMode: String, CaseIterable, Identifiable {
    case pdf = "Xuất PDF"
    case images = "Xuất Ảnh"

    var id: String { rawValue }
}

struct ScanFolder: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var icon: String
    var isSystem: Bool
}

struct ScannedPage: Identifiable, Codable, Hashable {
    var id: String
    var originalFileName: String
    var renderedFileName: String
    var filterMode: ScanFilterMode
    var brightness: Float
    var contrast: Float
    var rotationDegrees: Int
}

struct ScannedDocument: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var folderId: String
    var createdAt: TimeInterval
    var updatedAt: TimeInterval
    var pages: [ScannedPage]
}
