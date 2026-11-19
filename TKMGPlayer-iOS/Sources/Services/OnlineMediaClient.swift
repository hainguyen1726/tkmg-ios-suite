import Foundation

struct ResolvedOnlineTrack: Identifiable, Codable, Hashable {
    let index: Int
    let id: String
    let title: String
    let uploader: String
    let duration: Double
    let thumbnail: String
    let url: String
    let streamAudioURL: String
    let streamVideoURL: String
    let isPlaylist: Bool?

    var isPlaylistItem: Bool { isPlaylist ?? false }

    enum CodingKeys: String, CodingKey {
        case index, id, title, uploader, duration, thumbnail, url
        case streamAudioURL = "stream_audio_url"
        case streamVideoURL = "stream_video_url"
        case isPlaylist = "is_playlist"
    }
}

struct ResolvedOnlineBatch: Codable {
    let type: String
    let searchType: String?
    let title: String
    let uploader: String
    let cover: String
    let count: Int
    let items: [ResolvedOnlineTrack]

    enum CodingKeys: String, CodingKey {
        case type, title, uploader, cover, count, items
        case searchType = "search_type"
    }
}

private struct ResolveRequest: Encodable {
    let url: String
    let force_playlist: Bool
}

private struct SearchRequest: Encodable {
    let query: String
    let limit: Int
    let search_type: String
}

private struct DownloadRequest: Encodable {
    let url: String
    let format: String
    let title: String
    let quality: String?
    let prefix_index: Int?
    let pad_width: Int?
}

private struct DownloadStartResponse: Decodable {
    let job_id: String?
    let error: String?
}

private struct JobStatusResponse: Decodable {
    let status: String
    let filename: String?
    let error: String?
}

private struct ErrorEnvelope: Decodable {
    let error: String?
}

final class OnlineMediaClient {
    let baseURL: String

    init(baseURL: String = "https://download.netslive.com") {
        self.baseURL = baseURL
    }

    func resolve(url: String, forcePlaylist: Bool = false) async throws -> ResolvedOnlineBatch {
        let payload = ResolveRequest(url: url.trimmingCharacters(in: .whitespacesAndNewlines), force_playlist: forcePlaylist)
        return try await postBatch(path: "/api/app/resolve", body: payload, timeout: 120)
    }

    func searchYoutube(query: String, limit: Int = 20, searchType: String = "video") async throws -> ResolvedOnlineBatch {
        let payload = SearchRequest(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            limit: min(max(limit, 1), 30),
            search_type: searchType
        )
        return try await postBatch(path: "/api/app/search", body: payload, timeout: 60)
    }

    private func postBatch<T: Encodable>(path: String, body: T, timeout: TimeInterval) async throws -> ResolvedOnlineBatch {
        guard let endpoint = URL(string: "\(baseURL)\(path)") else {
            throw NSError(domain: "TKMGOnline", code: 1, userInfo: [NSLocalizedDescriptionKey: "URL máy chủ không hợp lệ"])
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let httpCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200...299).contains(httpCode) {
            let msg = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error) ?? "Lỗi phân giải (HTTP \(httpCode))"
            throw NSError(domain: "TKMGOnline", code: httpCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let batch = try JSONDecoder().decode(ResolvedOnlineBatch.self, from: data)
        if batch.items.isEmpty {
            throw NSError(domain: "TKMGOnline", code: 2, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy bài nào"])
        }
        return batch
    }

    func downloadTrack(
        track: ResolvedOnlineTrack,
        format: String,
        totalCount: Int,
        targetDir: URL,
        isFromPlaylist: Bool,
        quality: String? = nil,
        onStatus: @escaping (String) -> Void
    ) async throws -> URL {
        guard let startURL = URL(string: "\(baseURL)/api/download") else {
            throw NSError(domain: "TKMGOnline", code: 3, userInfo: [NSLocalizedDescriptionKey: "URL tải không hợp lệ"])
        }

        var startReq = URLRequest(url: startURL)
        startReq.httpMethod = "POST"
        startReq.timeoutInterval = 30
        startReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let padWidth = max(2, String(totalCount).count)
        let sendQuality = (format == "video" && quality != nil && quality != "best") ? quality : nil
        let payload = DownloadRequest(
            url: track.url,
            format: format,
            title: track.title,
            quality: sendQuality,
            prefix_index: isFromPlaylist ? track.index : nil,
            pad_width: isFromPlaylist ? padWidth : nil
        )
        startReq.httpBody = try JSONEncoder().encode(payload)

        onStatus("Đang gửi yêu cầu...")
        let (startData, startResp) = try await URLSession.shared.data(for: startReq)
        let startCode = (startResp as? HTTPURLResponse)?.statusCode ?? 0
        let startDecoded = try JSONDecoder().decode(DownloadStartResponse.self, from: startData)
        guard (200...299).contains(startCode), let jobId = startDecoded.job_id else {
            throw NSError(domain: "TKMGOnline", code: startCode, userInfo: [NSLocalizedDescriptionKey: startDecoded.error ?? "Không thể tạo tác vụ tải"])
        }

        guard let statusURL = URL(string: "\(baseURL)/api/status/\(jobId)") else {
            throw NSError(domain: "TKMGOnline", code: 4, userInfo: [NSLocalizedDescriptionKey: "URL kiểm tra trạng thái không hợp lệ"])
        }

        var finalFileName: String?
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            let (stData, stResp) = try await URLSession.shared.data(from: statusURL)
            let stCode = (stResp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(stCode) else {
                throw NSError(domain: "TKMGOnline", code: stCode, userInfo: [NSLocalizedDescriptionKey: "Lỗi kiểm tra tiến trình"])
            }
            let st = try JSONDecoder().decode(JobStatusResponse.self, from: stData)
            switch st.status {
            case "queued":
                onStatus("Đang chờ máy chủ...")
            case "downloading":
                onStatus("Đang tách \(format == "audio" ? "MP3" : "MP4")...")
            case "processing":
                onStatus("Đang xử lý tệp...")
            case "done":
                finalFileName = st.filename
            case "error":
                throw NSError(domain: "TKMGOnline", code: 5, userInfo: [NSLocalizedDescriptionKey: st.error ?? "Tải xuống thất bại"])
            default:
                break
            }
            if finalFileName != nil { break }
        }

        guard let serverName = finalFileName else {
            throw NSError(domain: "TKMGOnline", code: 6, userInfo: [NSLocalizedDescriptionKey: "Hết thời gian chờ"])
        }

        onStatus("Đang lưu vào Tệp iPhone...")
        guard let fileEndpoint = URL(string: "\(baseURL)/api/file/\(jobId)") else {
            throw NSError(domain: "TKMGOnline", code: 7, userInfo: [NSLocalizedDescriptionKey: "URL tệp không hợp lệ"])
        }

        let (tempURL, dlResp) = try await URLSession.shared.download(from: fileEndpoint)
        let dlCode = (dlResp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(dlCode) else {
            throw NSError(domain: "TKMGOnline", code: dlCode, userInfo: [NSLocalizedDescriptionKey: "Tải tệp về máy thất bại (HTTP \(dlCode))"])
        }

        let fm = FileManager.default
        if !fm.fileExists(atPath: targetDir.path) {
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }
        let cleanName = sanitizeFilename(serverName)
        let dest = uniqueFileURL(in: targetDir, desiredName: cleanName)
        try fm.moveItem(at: tempURL, to: dest)
        return dest
    }

    private func sanitizeFilename(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let parts = name.components(separatedBy: forbidden)
        let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "download.mp3" : joined
    }

    private func uniqueFileURL(in dir: URL, desiredName: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(desiredName)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        let base = (desiredName as NSString).deletingPathExtension
        let ext = (desiredName as NSString).pathExtension
        var count = 2
        while fm.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(base) (\(count))" : "\(base) (\(count)).\(ext)"
            candidate = dir.appendingPathComponent(nextName)
            count += 1
        }
        return candidate
    }
}
