import AVFoundation
import Foundation
import SwiftUI

private struct LibrarySnapshot: Codable {
    var items: [MediaItem]
    var folders: [FolderSource]
    var playlists: [Playlist]
    var preferFileName: Bool
}

@MainActor
final class MediaLibraryStore: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var folders: [FolderSource] = []
    @Published var playlists: [Playlist] = []
    @Published var isScanning = false
    @Published var preferFileName = true
    @Published var statusMessage: String?

    private static let supportedAudioExts: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"]
    private static let supportedVideoExts: Set<String> = ["mp4", "m4v", "mov", "mkv", "avi"]

    private let fm = FileManager.default

    private var documentsURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var stateFileURL: URL {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("tkmg_player_state.json")
    }

    init() {
        loadState()
        ensureDefaultFolder()
        Task {
            await scanAllSources()
        }
    }

    private func ensureDefaultFolder() {
        if !folders.contains(where: { $0.isSandboxBuiltIn }) {
            let builtIn = FolderSource(
                id: "builtin-documents",
                name: "TKMG Player (Tệp / Files)",
                isSandboxBuiltIn: true,
                bookmarkData: nil,
                isEnabled: true
            )
            folders.insert(builtIn, at: 0)
            saveState()
        }
    }

    func resolveURL(for item: MediaItem) -> (url: URL, isSecurityScoped: Bool)? {
        if let remote = item.remoteStreamURL, let remoteURL = URL(string: remote) {
            return (remoteURL, false)
        }
        if let rel = item.relativePath {
            let candidate = documentsURL.appendingPathComponent(rel)
            if fm.fileExists(atPath: candidate.path) {
                return (candidate, false)
            }
        }
        if let bm = item.bookmarkData {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bm, bookmarkDataIsStale: &stale) {
                return (url, true)
            }
        }
        return nil
    }

    func importFiles(_ urls: [URL]) async {
        var importedCount = 0
        let inboxDir = documentsURL.appendingPathComponent("Imported Media", isDirectory: true)
        try? fm.createDirectory(at: inboxDir, withIntermediateDirectories: true)

        for srcURL in urls {
            let needsStop = srcURL.startAccessingSecurityScopedResource()
            defer {
                if needsStop { srcURL.stopAccessingSecurityScopedResource() }
            }
            let dest = uniqueDestinationURL(in: inboxDir, desiredName: srcURL.lastPathComponent)
            do {
                try fm.copyItem(at: srcURL, to: dest)
                importedCount += 1
            } catch {
                // Ignore duplicate/unreadable files cleanly
            }
        }

        await scanAllSources()
        if importedCount > 0 {
            statusMessage = "Đã nhập \(importedCount) file vào TKMG Player"
        }
    }

    func linkExternalFolder(_ folderURL: URL) async {
        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { folderURL.stopAccessingSecurityScopedResource() }
        }
        guard let bookmark = try? folderURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            statusMessage = "Không thể lưu quyền truy cập thư mục"
            return
        }
        let id = "ext-\(folderURL.lastPathComponent)-\(Int(Date().timeIntervalSince1970))"
        if !folders.contains(where: { $0.name == folderURL.lastPathComponent && !$0.isSandboxBuiltIn }) {
            folders.append(
                FolderSource(
                    id: id,
                    name: folderURL.lastPathComponent,
                    isSandboxBuiltIn: false,
                    bookmarkData: bookmark,
                    isEnabled: true
                )
            )
            saveState()
        }
        await scanAllSources()
        statusMessage = "Đã liên kết thư mục \(folderURL.lastPathComponent)"
    }

    func toggleFolder(_ folderId: String) {
        guard let idx = folders.firstIndex(where: { $0.id == folderId }) else { return }
        folders[idx].isEnabled.toggle()
        saveState()
        Task { await scanAllSources() }
    }

    func removeExternalFolder(_ folderId: String) {
        folders.removeAll { $0.id == folderId && !$0.isSandboxBuiltIn }
        saveState()
        Task { await scanAllSources() }
    }

    func scanAllSources() async {
        isScanning = true
        defer { isScanning = false }

        let oldById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var discovered: [MediaItem] = []
        var seenIds = Set<String>()

        for folder in folders where folder.isEnabled {
            if folder.isSandboxBuiltIn {
                let found = await scanDirectory(
                    baseURL: documentsURL,
                    folderLabel: folder.name,
                    isSandbox: true
                )
                for item in found where seenIds.insert(item.id).inserted {
                    discovered.append(mergeSavedProgress(newItem: item, oldMap: oldById))
                }
            } else if let bm = folder.bookmarkData {
                var stale = false
                if let extURL = try? URL(resolvingBookmarkData: bm, bookmarkDataIsStale: &stale) {
                    let accessed = extURL.startAccessingSecurityScopedResource()
                    let found = await scanDirectory(
                        baseURL: extURL,
                        folderLabel: folder.name,
                        isSandbox: false
                    )
                    if accessed { extURL.stopAccessingSecurityScopedResource() }
                    for item in found where seenIds.insert(item.id).inserted {
                        discovered.append(mergeSavedProgress(newItem: item, oldMap: oldById))
                    }
                }
            }
        }

        let playlistItemIDs = Set(playlists.flatMap { $0.itemIDs })
        for oldItem in items where oldItem.remoteStreamURL != nil && playlistItemIDs.contains(oldItem.id) {
            if seenIds.insert(oldItem.id).inserted {
                discovered.append(oldItem)
            }
        }

        items = discovered
        saveState()
    }

    private func mergeSavedProgress(newItem: MediaItem, oldMap: [String: MediaItem]) -> MediaItem {
        guard let old = oldMap[newItem.id] else { return newItem }
        var merged = newItem
        merged.positionSec = old.positionSec
        merged.isCompleted = old.isCompleted
        merged.isFavorite = old.isFavorite
        merged.lastPlayedAt = old.lastPlayedAt
        if old.title != nil { merged.title = old.title }
        return merged
    }

    private func scanDirectory(baseURL: URL, folderLabel: String, isSandbox: Bool) async -> [MediaItem] {
        var collected: [MediaItem] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fm.enumerator(
            at: baseURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var candidateURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if Self.supportedAudioExts.contains(ext) || Self.supportedVideoExts.contains(ext) {
                candidateURLs.append(fileURL)
            }
        }

        for fileURL in candidateURLs {
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile ?? true else { continue }
            let ext = fileURL.pathExtension.lowercased()
            let kind: MediaKind = Self.supportedVideoExts.contains(ext) ? .video : .audio
            let size = Int64(values?.fileSize ?? 0)
            let modAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0

            let asset = AVURLAsset(url: fileURL)
            let durationCM = try? await asset.load(.duration)
            let durationSec = durationCM.map { CMTimeGetSeconds($0) }.flatMap { $0.isFinite ? $0 : 0 } ?? 0
            let metadata = (try? await asset.load(.commonMetadata)) ?? []
            var title: String?
            var artist: String?
            var album: String?
            for meta in metadata {
                if meta.commonKey == .commonKeyTitle {
                    title = try? await meta.load(.stringValue)
                } else if meta.commonKey == .commonKeyArtist {
                    artist = try? await meta.load(.stringValue)
                } else if meta.commonKey == .commonKeyAlbumName {
                    album = try? await meta.load(.stringValue)
                }
            }

            let relPath: String?
            let bmData: Data?
            let stableId: String
            if isSandbox {
                let prefix = baseURL.standardizedFileURL.path + "/"
                let full = fileURL.standardizedFileURL.path
                let rel = full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : fileURL.lastPathComponent
                relPath = rel
                bmData = nil
                stableId = "doc:\(rel)"
            } else {
                relPath = nil
                bmData = try? fileURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                stableId = "ext:\(fileURL.lastPathComponent):\(size)"
            }

            let parentFolderName = fileURL.deletingLastPathComponent().lastPathComponent
            let label = parentFolderName.isEmpty ? folderLabel : parentFolderName

            collected.append(
                MediaItem(
                    id: stableId,
                    relativePath: relPath,
                    bookmarkData: bmData,
                    fileName: fileURL.lastPathComponent,
                    folderName: label,
                    kind: kind,
                    sizeBytes: size,
                    modifiedAt: modAt,
                    durationSec: durationSec,
                    title: title,
                    artist: artist,
                    album: album,
                    positionSec: 0,
                    isCompleted: false,
                    isFavorite: false,
                    lastPlayedAt: 0
                )
            )
        }
        return collected
    }

    func updateProgress(itemID: String, positionSec: Double, durationSec: Double) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[idx].positionSec = positionSec
        if durationSec > 0 {
            items[idx].durationSec = durationSec
            if positionSec / durationSec >= 0.97 {
                items[idx].isCompleted = true
            }
        }
        items[idx].lastPlayedAt = Date().timeIntervalSince1970
        saveState()
    }

    func toggleFavorite(_ itemID: String) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[idx].isFavorite.toggle()
        saveState()
    }

    func deleteItem(_ item: MediaItem) {
        if item.remoteStreamURL == nil, let resolved = resolveURL(for: item) {
            if resolved.isSecurityScoped {
                _ = resolved.url.startAccessingSecurityScopedResource()
            }
            try? fm.removeItem(at: resolved.url)
            if resolved.isSecurityScoped {
                resolved.url.stopAccessingSecurityScopedResource()
            }
        }
        items.removeAll { $0.id == item.id }
        for i in playlists.indices {
            playlists[i].itemIDs.removeAll { $0 == item.id }
        }
        saveState()
    }

    func applyBatchRename(_ rows: [RenamePreviewRow]) async {
        var renamed = 0
        for row in rows where row.isSelected && row.hasChanges {
            guard let resolved = resolveURL(for: row.item) else { continue }
            if resolved.isSecurityScoped {
                _ = resolved.url.startAccessingSecurityScopedResource()
            }
            defer {
                if resolved.isSecurityScoped {
                    resolved.url.stopAccessingSecurityScopedResource()
                }
            }
            let targetURL = uniqueDestinationURL(
                in: resolved.url.deletingLastPathComponent(),
                desiredName: row.newFileName
            )
            do {
                try fm.moveItem(at: resolved.url, to: targetURL)
                renamed += 1
            } catch {
                // Skip locked or read-only items
            }
        }
        await scanAllSources()
        statusMessage = "Đã chuẩn hóa tên \(renamed) file"
    }

    func createPlaylist(name: String, initialItemIDs: [String] = []) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pl = Playlist(
            id: UUID().uuidString,
            name: trimmed,
            createdAt: Date().timeIntervalSince1970,
            itemIDs: initialItemIDs
        )
        playlists.append(pl)
        saveState()
    }

    func addItems(_ itemIDs: [String], toPlaylist playlistID: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var current = playlists[idx].itemIDs
        for id in itemIDs where !current.contains(id) {
            current.append(id)
        }
        playlists[idx].itemIDs = current
        saveState()
    }

    func deletePlaylist(_ playlistID: String) {
        playlists.removeAll { $0.id == playlistID }
        saveState()
    }

    func getOnlineDownloadDir(subFolderName: String?) -> URL {
        let base = documentsURL.appendingPathComponent("Online Downloads", isDirectory: true)
        let forbidden = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleanSub = (subFolderName ?? "")
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let target: URL
        if !cleanSub.isEmpty {
            target = base.appendingPathComponent(String(cleanSub.prefix(50)), isDirectory: true)
        } else {
            target = base
        }
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    func saveOnlinePlaylistToLibrary(name: String, tracks: [ResolvedOnlineTrack], asVideo: Bool) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let plName = cleanName.isEmpty ? "Playlist Online" : cleanName
        let now = Date().timeIntervalSince1970
        var newIDs: [String] = []

        for t in tracks {
            let streamURL = asVideo ? t.streamVideoURL : t.streamAudioURL
            let id = "online:\(asVideo ? "v" : "a"):\(t.id):\(abs(streamURL.hashValue))"
            let padded = String(format: "%02d", t.index)
            let fileName = "\(padded) - \(t.title).\(asVideo ? "mp4" : "m4a")"
            let item = MediaItem(
                id: id,
                relativePath: nil,
                bookmarkData: nil,
                remoteStreamURL: streamURL,
                fileName: fileName,
                folderName: "Online",
                kind: asVideo ? .video : .audio,
                sizeBytes: 0,
                modifiedAt: now,
                durationSec: t.duration,
                title: t.title,
                artist: t.uploader.isEmpty ? plName : t.uploader,
                album: plName,
                positionSec: 0,
                isCompleted: false,
                isFavorite: false,
                lastPlayedAt: 0
            )
            if !items.contains(where: { $0.id == id }) {
                items.append(item)
            }
            newIDs.append(id)
        }

        createPlaylist(name: plName, initialItemIDs: newIDs)
        statusMessage = "Đã lưu Playlist Online \"\(plName)\" (\(newIDs.count) bài)"
    }

    func itemIDForDownloadedURL(_ fileURL: URL) -> String? {
        let prefix = documentsURL.standardizedFileURL.path + "/"
        let full = fileURL.standardizedFileURL.path
        guard full.hasPrefix(prefix) else { return nil }
        let rel = String(full.dropFirst(prefix.count))
        return "doc:\(rel)"
    }

    func filteredAndSortedItems(
        query: String,
        filter: MediaFilter,
        sortMode: MediaSortMode,
        playlistID: String? = nil
    ) -> [MediaItem] {
        var result = items

        if let playlistID, let pl = playlists.first(where: { $0.id == playlistID }) {
            let map = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            result = pl.itemIDs.compactMap { map[$0] }
        } else {
            result = result.filter { $0.remoteStreamURL == nil }
        }

        switch filter {
        case .all:
            break
        case .audio:
            result = result.filter { $0.kind == .audio }
        case .video:
            result = result.filter { $0.kind == .video }
        case .unfinished:
            result = result.filter { !$0.isCompleted }
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty {
            result = result.filter {
                $0.fileName.lowercased().contains(trimmed)
                || ($0.title?.lowercased().contains(trimmed) ?? false)
                || $0.folderName.lowercased().contains(trimmed)
            }
        }

        switch sortMode {
        case .natural:
            result.sort {
                RustBridge.naturalCompare(
                    $0.displayTitle(preferFileName: preferFileName),
                    $1.displayTitle(preferFileName: preferFileName)
                ) == .orderedAscending
            }
        case .name:
            result.sort {
                $0.displayTitle(preferFileName: preferFileName)
                    .localizedCaseInsensitiveCompare($1.displayTitle(preferFileName: preferFileName)) == .orderedAscending
            }
        case .dateDesc:
            result.sort { $0.modifiedAt > $1.modifiedAt }
        case .duration:
            result.sort { $0.durationSec > $1.durationSec }
        case .size:
            result.sort { $0.sizeBytes > $1.sizeBytes }
        }

        return result
    }

    private func uniqueDestinationURL(in dir: URL, desiredName: String) -> URL {
        var candidate = dir.appendingPathComponent(desiredName)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = (desiredName as NSString).deletingPathExtension
        let ext = (desiredName as NSString).pathExtension
        var count = 1
        while fm.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(base) (\(count))" : "\(base) (\(count)).\(ext)"
            candidate = dir.appendingPathComponent(nextName)
            count += 1
        }
        return candidate
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateFileURL),
              let snap = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) else {
            return
        }
        items = snap.items
        folders = snap.folders
        playlists = snap.playlists
        preferFileName = snap.preferFileName
    }

    func saveState() {
        let snap = LibrarySnapshot(
            items: items,
            folders: folders,
            playlists: playlists,
            preferFileName: preferFileName
        )
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: stateFileURL, options: .atomic)
        }
    }
}
