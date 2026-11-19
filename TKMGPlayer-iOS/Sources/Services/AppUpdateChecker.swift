import Foundation
import SwiftUI

struct RemoteAppInfo: Equatable {
    let id: String
    let name: String
    let version: String
    let buildCode: Int?
    let apkUrl: String
    let apkFileName: String
    let apkSizeLabel: String
    let whatsNew: String

    var versionTag: String {
        "\(version)_\(buildCode ?? 0)"
    }
}

private struct RemoteManifestPayload: Decodable {
    let apps: [RemoteManifestItem]
}

private struct RemoteManifestItem: Decodable {
    let id: String
    let name: String?
    let version: String?
    let buildCode: Int?
    let apkUrl: String?
    let apkFileName: String?
    let apkSizeLabel: String?
    let whatsNew: String?
    let summary: String?
}

enum AppUpdateLogic {
    static func parseAppEntry(from data: Data, appId: String) -> RemoteAppInfo? {
        guard let decoded = try? JSONDecoder().decode(RemoteManifestPayload.self, from: data),
              let match = decoded.apps.first(where: { $0.id == appId }),
              let rawVersion = match.version?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawVersion.isEmpty else {
            return nil
        }
        return RemoteAppInfo(
            id: match.id,
            name: match.name ?? appId,
            version: rawVersion,
            buildCode: match.buildCode,
            apkUrl: match.apkUrl ?? "",
            apkFileName: match.apkFileName ?? "",
            apkSizeLabel: match.apkSizeLabel ?? "",
            whatsNew: match.whatsNew ?? match.summary ?? ""
        )
    }

    static func compareSemVer(_ remote: String, _ local: String) -> Int {
        func parseParts(_ text: String) -> [Int] {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let stripped = (trimmed.hasPrefix("v") || trimmed.hasPrefix("V")) ? String(trimmed.dropFirst()) : trimmed
            return stripped.split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" }).map { seg in
                let digits = seg.prefix(while: { $0.isNumber })
                return Int(digits) ?? 0
            }
        }
        let rParts = parseParts(remote)
        let lParts = parseParts(local)
        let count = max(max(rParts.count, lParts.count), 3)
        for i in 0..<count {
            let rv = i < rParts.count ? rParts[i] : 0
            let lv = i < lParts.count ? lParts[i] : 0
            if rv != lv {
                return rv > lv ? 1 : -1
            }
        }
        return 0
    }

    static func isNewerUpdate(remote: RemoteAppInfo, localVersion: String, localBuildCode: Int) -> Bool {
        if let remoteBuild = remote.buildCode, remoteBuild > 0, localBuildCode > 0 {
            if remoteBuild > localBuildCode { return true }
            if remoteBuild < localBuildCode { return false }
        }
        return compareSemVer(remote.version, localVersion) > 0
    }
}

@MainActor
final class AppUpdateChecker: ObservableObject {
    static let manifestURLString = "https://mobile-app.netslive.com/apps.json"
    static let webDownloadURL = URL(string: "https://mobile-app.netslive.com/#apps")!

    @Published var isChecking = false
    @Published var bannerUpdate: RemoteAppInfo?
    @Published var alertUpdate: RemoteAppInfo?
    @Published var manualMessage: String?

    let appId: String
    let localVersion: String
    let localBuildCode: Int

    private let skippedTagKey = "tkmg_skipped_update_tag"
    private let autoResumeIntervalSec: TimeInterval = 5 * 60
    private var lastSessionCheckDate: Date?
    private var dismissedSessionTag: String?

    init(appId: String) {
        self.appId = appId
        let info = Bundle.main.infoDictionary
        self.localVersion = (info?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        self.localBuildCode = Int((info?["CFBundleVersion"] as? String) ?? "1") ?? 1
    }

    func checkOnLaunchIfNeeded() {
        checkOnResumeIfNeeded()
    }

    func checkOnResumeIfNeeded() {
        if let last = lastSessionCheckDate, Date().timeIntervalSince(last) < autoResumeIntervalSec {
            return
        }
        Task {
            await checkForUpdates(manual: false)
        }
    }

    func checkForUpdates(manual: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let urlStr = "\(Self.manifestURLString)?t=\(Int(Date().timeIntervalSince1970))"
        guard let url = URL(string: urlStr) else { return }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5.0)
        req.setValue("TKMG-iOS-Updater", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                if manual {
                    manualMessage = "Máy chủ cập nhật phản hồi mã \(http.statusCode)."
                }
                return
            }

            lastSessionCheckDate = Date()

            if let entry = AppUpdateLogic.parseAppEntry(from: data, appId: appId),
               AppUpdateLogic.isNewerUpdate(remote: entry, localVersion: localVersion, localBuildCode: localBuildCode) {
                if manual {
                    UserDefaults.standard.removeObject(forKey: skippedTagKey)
                    dismissedSessionTag = nil
                }
                let skippedTag = UserDefaults.standard.string(forKey: skippedTagKey)
                bannerUpdate = entry
                if manual || (skippedTag != entry.versionTag && dismissedSessionTag != entry.versionTag) {
                    alertUpdate = entry
                }
            } else {
                bannerUpdate = nil
                alertUpdate = nil
                if manual {
                    manualMessage = "Bạn đang dùng phiên bản mới nhất (v\(localVersion))."
                }
            }
        } catch {
            if manual {
                manualMessage = "Không kiểm tra được bản mới. Vui lòng kiểm tra kết nối mạng."
            }
        }
    }

    func skipCurrentAlert() {
        if let upd = alertUpdate ?? bannerUpdate {
            UserDefaults.standard.set(upd.versionTag, forKey: skippedTagKey)
        }
        alertUpdate = nil
        bannerUpdate = nil
    }

    func dismissAlert() {
        if let upd = alertUpdate {
            dismissedSessionTag = upd.versionTag
        }
        alertUpdate = nil
    }
}

struct UpdateAvailableBannerView: View {
    let update: RemoteAppInfo
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.black)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Đã có bản mới v\(update.version)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.black)
                    if !update.apkSizeLabel.isEmpty {
                        Text("Dung lượng \(update.apkSizeLabel) • Chạm để xem")
                            .font(.caption2)
                            .foregroundColor(.black.opacity(0.8))
                    }
                }
                Spacer()
                Text("Xem")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.top, 6)
        }
        .buttonStyle(.plain)
    }
}

struct UpdateAlertOverlayModifier: ViewModifier {
    @ObservedObject var checker: AppUpdateChecker
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .alert(
                "Đã có bản mới v\(checker.alertUpdate?.version ?? "")",
                isPresented: Binding(
                    get: { checker.alertUpdate != nil },
                    set: { if !$0 { checker.dismissAlert() } }
                )
            ) {
                Button("Mở trang tải (Sideloadly)") {
                    checker.dismissAlert()
                    openURL(AppUpdateChecker.webDownloadURL)
                }
                Button("Bỏ qua bản này", role: .destructive) {
                    checker.skipCurrentAlert()
                }
                Button("Để sau", role: .cancel) {
                    checker.dismissAlert()
                }
            } message: {
                if let upd = checker.alertUpdate {
                    let sizeText = upd.apkSizeLabel.isEmpty ? "" : " (\(upd.apkSizeLabel))"
                    let detail = upd.whatsNew.isEmpty ? "" : "\n\n\(upd.whatsNew)"
                    Text("Bản đang cài: v\(checker.localVersion) → Mới: v\(upd.version)\(sizeText).\(detail)\n\nTrên iOS, hãy tải file .ipa từ mobile-app.netslive.com và cài đè bằng Sideloadly (dữ liệu cũ vẫn giữ nguyên).")
                }
            }
            .alert(
                "Kiểm tra cập nhật",
                isPresented: Binding(
                    get: { checker.manualMessage != nil },
                    set: { if !$0 { checker.manualMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { checker.manualMessage = nil }
            } message: {
                Text(checker.manualMessage ?? "")
            }
    }
}

extension View {
    func withAppUpdateAlerts(checker: AppUpdateChecker) -> some View {
        modifier(UpdateAlertOverlayModifier(checker: checker))
    }
}
