import Foundation
import Photos
import SwiftUI
import UIKit

private struct ScannerSnapshot: Codable {
    var folders: [ScanFolder]
    var documents: [ScannedDocument]
}

@MainActor
final class ScanStore: ObservableObject {
    @Published var folders: [ScanFolder] = []
    @Published var documents: [ScannedDocument] = []
    @Published var defaultFilter: ScanFilterMode = .magicColor
    @Published var isProcessing = false
    @Published var toastMessage: String?

    private let fm = FileManager.default

    private var baseDir: URL {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("TKMGScanner", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var pagesDir: URL {
        let dir = baseDir.appendingPathComponent("pages", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var stateFileURL: URL {
        baseDir.appendingPathComponent("scanner_state.json")
    }

    init() {
        loadState()
        ensureDefaultFolders()
    }

    private func ensureDefaultFolders() {
        if folders.isEmpty {
            folders = [
                ScanFolder(id: "all", name: "Tất cả", icon: "tray.full.fill", isSystem: true),
                ScanFolder(id: "docs-id", name: "Giấy tờ & CCCD", icon: "person.text.rectangle.fill", isSystem: true),
                ScanFolder(id: "contracts", name: "Hợp đồng", icon: "doc.text.fill", isSystem: true),
                ScanFolder(id: "invoices", name: "Hóa đơn", icon: "doc.plaintext.fill", isSystem: true)
            ]
            saveState()
        }
    }

    func createFolder(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folders.append(ScanFolder(id: UUID().uuidString, name: trimmed, icon: "folder.fill", isSystem: false))
        saveState()
    }

    func renderedImage(for page: ScannedPage) -> UIImage? {
        UIImage(contentsOfFile: pagesDir.appendingPathComponent(page.renderedFileName).path)
    }

    func originalImage(for page: ScannedPage) -> UIImage? {
        UIImage(contentsOfFile: pagesDir.appendingPathComponent(page.originalFileName).path)
    }

    func addScannedDocument(
        images: [UIImage],
        title: String? = nil,
        folderId: String = "docs-id",
        intoDocumentID: String? = nil
    ) async -> ScannedDocument? {
        guard !images.isEmpty else { return nil }
        isProcessing = true
        defer { isProcessing = false }

        let targetFolderId = folderId == "all" ? "docs-id" : folderId
        var newPages: [ScannedPage] = []

        for img in images {
            let pageId = UUID().uuidString
            let origName = "\(pageId)_orig.jpg"
            let rendName = "\(pageId)_rend.jpg"

            let normalized = RustImageProcessor.normalizedAndRotated(image: img, rotationDegrees: 0, maxEdgePx: 2600)
            if let origData = normalized.jpegData(compressionQuality: 0.94) {
                try? origData.write(to: pagesDir.appendingPathComponent(origName), options: .atomic)
            }

            let filter = defaultFilter
            let processed = await Task.detached(priority: .userInitiated) {
                RustImageProcessor.process(
                    image: normalized,
                    mode: filter,
                    brightnessOffset: 0.0,
                    contrastScale: 1.0,
                    rotationDegrees: 0,
                    maxEdgePx: 2400
                )
            }.value

            if let rendData = processed.jpegData(compressionQuality: 0.92) {
                try? rendData.write(to: pagesDir.appendingPathComponent(rendName), options: .atomic)
            }

            newPages.append(
                ScannedPage(
                    id: pageId,
                    originalFileName: origName,
                    renderedFileName: rendName,
                    filterMode: filter,
                    brightness: 0.0,
                    contrast: 1.0,
                    rotationDegrees: 0
                )
            )
        }

        let now = Date().timeIntervalSince1970
        if let docId = intoDocumentID,
           let idx = documents.firstIndex(where: { $0.id == docId }) {
            documents[idx].pages.append(contentsOf: newPages)
            documents[idx].updatedAt = now
            saveState()
            return documents[idx]
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM_HHmm"
        let docTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? title!
            : "TaiLieu_\(formatter.string(from: Date()))"

        let doc = ScannedDocument(
            id: UUID().uuidString,
            title: docTitle,
            folderId: targetFolderId,
            createdAt: now,
            updatedAt: now,
            pages: newPages
        )
        documents.insert(doc, at: 0)
        saveState()
        return doc
    }

    func updatePage(
        documentID: String,
        pageID: String,
        mode: ScanFilterMode,
        brightness: Float,
        contrast: Float,
        rotationDegrees: Int
    ) async {
        guard let dIdx = documents.firstIndex(where: { $0.id == documentID }),
              let pIdx = documents[dIdx].pages.firstIndex(where: { $0.id == pageID }),
              let orig = originalImage(for: documents[dIdx].pages[pIdx]) else {
            return
        }
        isProcessing = true
        defer { isProcessing = false }

        let rendered = await Task.detached(priority: .userInitiated) {
            RustImageProcessor.process(
                image: orig,
                mode: mode,
                brightnessOffset: brightness,
                contrastScale: contrast,
                rotationDegrees: rotationDegrees,
                maxEdgePx: 2400
            )
        }.value

        let rendName = documents[dIdx].pages[pIdx].renderedFileName
        if let data = rendered.jpegData(compressionQuality: 0.92) {
            try? data.write(to: pagesDir.appendingPathComponent(rendName), options: .atomic)
        }

        documents[dIdx].pages[pIdx].filterMode = mode
        documents[dIdx].pages[pIdx].brightness = brightness
        documents[dIdx].pages[pIdx].contrast = contrast
        documents[dIdx].pages[pIdx].rotationDegrees = ((rotationDegrees % 360) + 360) % 360
        documents[dIdx].updatedAt = Date().timeIntervalSince1970
        saveState()
    }

    func applyStyleToAllPages(documentID: String, mode: ScanFilterMode, brightness: Float, contrast: Float) async {
        guard let dIdx = documents.firstIndex(where: { $0.id == documentID }) else { return }
        let pages = documents[dIdx].pages
        for page in pages {
            await updatePage(
                documentID: documentID,
                pageID: page.id,
                mode: mode,
                brightness: brightness,
                contrast: contrast,
                rotationDegrees: page.rotationDegrees
            )
        }
        toastMessage = "Đã áp dụng bộ lọc cho tất cả \(pages.count) trang"
    }

    func movePage(documentID: String, fromIndex: Int, delta: Int) {
        guard let dIdx = documents.firstIndex(where: { $0.id == documentID }) else { return }
        let toIndex = fromIndex + delta
        guard documents[dIdx].pages.indices.contains(fromIndex),
              documents[dIdx].pages.indices.contains(toIndex) else { return }
        documents[dIdx].pages.swapAt(fromIndex, toIndex)
        documents[dIdx].updatedAt = Date().timeIntervalSince1970
        saveState()
    }

    func deletePage(documentID: String, pageID: String) {
        guard let dIdx = documents.firstIndex(where: { $0.id == documentID }),
              let pIdx = documents[dIdx].pages.firstIndex(where: { $0.id == pageID }) else { return }
        let page = documents[dIdx].pages[pIdx]
        try? fm.removeItem(at: pagesDir.appendingPathComponent(page.originalFileName))
        try? fm.removeItem(at: pagesDir.appendingPathComponent(rawBackupName(for: page.originalFileName)))
        try? fm.removeItem(at: pagesDir.appendingPathComponent(page.renderedFileName))
        documents[dIdx].pages.remove(at: pIdx)
        documents[dIdx].updatedAt = Date().timeIntervalSince1970
        saveState()
    }

    private func rawBackupName(for originalFileName: String) -> String {
        "raw_\(originalFileName)"
    }

    func hasCropBackup(for page: ScannedPage) -> Bool {
        fm.fileExists(atPath: pagesDir.appendingPathComponent(rawBackupName(for: page.originalFileName)).path)
    }

    func applyPerspectiveCrop(
        documentID: String,
        pageID: String,
        quadNorm: [Float],
        rotationDegrees: Int,
        mode: ScanFilterMode,
        brightness: Float,
        contrast: Float
    ) async {
        guard let dIdx = documents.firstIndex(where: { $0.id == documentID }),
              let pIdx = documents[dIdx].pages.firstIndex(where: { $0.id == pageID }) else { return }
        let page = documents[dIdx].pages[pIdx]
        guard let orig = originalImage(for: page) else { return }

        isProcessing = true
        defer { isProcessing = false }

        let origURL = pagesDir.appendingPathComponent(page.originalFileName)
        let backupURL = pagesDir.appendingPathComponent(rawBackupName(for: page.originalFileName))
        if !fm.fileExists(atPath: backupURL.path) {
            try? fm.copyItem(at: origURL, to: backupURL)
        }

        let cropped: UIImage? = await Task.detached(priority: .userInitiated) {
            RustImageProcessor.perspectiveCrop(
                image: orig,
                quadNorm: quadNorm,
                rotationDegrees: rotationDegrees,
                maxEdgePx: 2400
            )
        }.value

        guard let cropped else {
            toastMessage = "Khung 4 góc không hợp lệ, vui lòng kéo lại"
            return
        }

        if let cropData = cropped.jpegData(compressionQuality: 0.95) {
            try? cropData.write(to: origURL, options: .atomic)
        }

        documents[dIdx].pages[pIdx].rotationDegrees = 0
        await updatePage(
            documentID: documentID,
            pageID: pageID,
            mode: mode,
            brightness: brightness,
            contrast: contrast,
            rotationDegrees: 0
        )
        toastMessage = "Đã cắt nắn 4 góc"
    }

    func resetPerspectiveCrop(
        documentID: String,
        pageID: String,
        mode: ScanFilterMode,
        brightness: Float,
        contrast: Float
    ) async {
        guard let dIdx = documents.firstIndex(where: { $0.id == documentID }),
              let pIdx = documents[dIdx].pages.firstIndex(where: { $0.id == pageID }) else { return }
        let page = documents[dIdx].pages[pIdx]
        let origURL = pagesDir.appendingPathComponent(page.originalFileName)
        let backupURL = pagesDir.appendingPathComponent(rawBackupName(for: page.originalFileName))
        guard fm.fileExists(atPath: backupURL.path) else { return }

        try? fm.removeItem(at: origURL)
        try? fm.copyItem(at: backupURL, to: origURL)
        try? fm.removeItem(at: backupURL)

        await updatePage(
            documentID: documentID,
            pageID: pageID,
            mode: mode,
            brightness: brightness,
            contrast: contrast,
            rotationDegrees: 0
        )
        toastMessage = "Đã khôi phục ảnh gốc"
    }

    func addIdCardA4Document(
        front: UIImage,
        back: UIImage,
        mode: ScanFilterMode,
        intoDocumentID: String? = nil
    ) async -> ScannedDocument? {
        isProcessing = true
        defer { isProcessing = false }

        let composed = await Task.detached(priority: .userInitiated) {
            RustImageProcessor.composeIdCardA4(front: front, back: back, mode: mode)
        }.value

        let prevDefault = defaultFilter
        defaultFilter = .original
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM_HHmm"
        let title = intoDocumentID == nil ? "CCCD_2Mat_\(formatter.string(from: Date()))" : nil
        let doc = await addScannedDocument(
            images: [composed],
            title: title,
            folderId: "docs-id",
            intoDocumentID: intoDocumentID
        )
        defaultFilter = prevDefault
        if doc != nil {
            toastMessage = "Đã ghép CCCD 2 mặt vào 1 trang A4"
        }
        return doc
    }

    func renameDocument(documentID: String, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = documents.firstIndex(where: { $0.id == documentID }) else { return }
        documents[idx].title = trimmed
        documents[idx].updatedAt = Date().timeIntervalSince1970
        saveState()
    }

    func moveDocumentFolder(documentID: String, folderId: String) {
        guard let idx = documents.firstIndex(where: { $0.id == documentID }) else { return }
        documents[idx].folderId = folderId
        documents[idx].updatedAt = Date().timeIntervalSince1970
        saveState()
    }

    func deleteDocument(_ doc: ScannedDocument) {
        for page in doc.pages {
            try? fm.removeItem(at: pagesDir.appendingPathComponent(page.originalFileName))
            try? fm.removeItem(at: pagesDir.appendingPathComponent(rawBackupName(for: page.originalFileName)))
            try? fm.removeItem(at: pagesDir.appendingPathComponent(page.renderedFileName))
        }
        documents.removeAll { $0.id == doc.id }
        saveState()
    }

    func savePagesToPhotos(_ doc: ScannedDocument) async {
        let images = doc.pages.compactMap { renderedImage(for: $0) }
        await saveCustomImagesToPhotos(images, format: .jpeg, asLongImage: false)
    }

    func saveCustomImagesToPhotos(_ images: [UIImage], format: ImageExportFormat, asLongImage: Bool) async {
        guard !images.isEmpty else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            toastMessage = "Cần cấp quyền Ảnh để lưu trang scan vào Thư viện"
            return
        }

        let targetImages: [UIImage]
        if asLongImage, images.count > 1, let longImg = RustImageProcessor.composeLongImage(pages: images) {
            targetImages = [longImg]
        } else {
            targetImages = images
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for img in targetImages {
                    if format == .png, let pngData = img.pngData() {
                        let req = PHAssetCreationRequest.forAsset()
                        req.addResource(with: .photo, data: pngData, options: nil)
                    } else {
                        PHAssetChangeRequest.creationRequestForAsset(from: img)
                    }
                }
            }
            toastMessage = asLongImage && images.count > 1
                ? "Đã lưu 1 Ảnh dài (\(format.fileExtension.uppercased())) vào Ảnh"
                : "Đã lưu \(targetImages.count) ảnh (\(format.fileExtension.uppercased())) vào Ảnh"
        } catch {
            toastMessage = "Không thể lưu ảnh: \(error.localizedDescription)"
        }
    }

    func filteredDocuments(folderId: String, query: String, sort: DocumentSortOrder) -> [ScannedDocument] {
        var result = documents
        if folderId != "all" {
            result = result.filter { $0.folderId == folderId }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            result = result.filter { $0.title.lowercased().contains(q) }
        }
        switch sort {
        case .updatedDesc:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .createdDesc:
            result.sort { $0.createdAt > $1.createdAt }
        case .titleAsc:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return result
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateFileURL),
              let snap = try? JSONDecoder().decode(ScannerSnapshot.self, from: data) else {
            return
        }
        folders = snap.folders
        documents = snap.documents
    }

    private func saveState() {
        let snap = ScannerSnapshot(folders: folders, documents: documents)
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: stateFileURL, options: .atomic)
        }
    }
}
