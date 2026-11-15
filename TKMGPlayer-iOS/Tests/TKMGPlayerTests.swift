import XCTest
@testable import TKMGPlayer

final class TKMGPlayerTests: XCTestCase {
    func testNaturalSortOrdersEpisodesCorrectly() {
        let input = ["Tap 10.mp3", "Tap 2.mp3", "Tap 1.mp3", "Tap 20.mp3"]
        let sorted = input.sorted {
            RustBridge.naturalCompare($0, $1) == .orderedAscending
        }
        XCTAssertEqual(sorted, ["Tap 1.mp3", "Tap 2.mp3", "Tap 10.mp3", "Tap 20.mp3"])
    }

    func testEpisodeNormalizationPadsSingleDigit() {
        let out = EpisodeNameHelper.normalizedEpisodeFileName(
            originalFileName: "Truyen hay (Tập 6 Q2) (MP3_70K).mp3",
            style: .normalizeEpisode,
            stripQualitySuffix: true
        )
        XCTAssertEqual(out, "Truyen hay (Tập 06 Q2).mp3")
    }

    func testDecodeResolvedOnlineBatch() throws {
        let json = """
        {
          "type": "playlist",
          "title": "Test Playlist",
          "uploader": "Channel",
          "cover": "https://example.com/c.jpg",
          "count": 1,
          "items": [
            {
              "index": 1,
              "id": "v1",
              "title": "Tập 1",
              "uploader": "Channel",
              "duration": 125.0,
              "thumbnail": "https://example.com/t.jpg",
              "url": "https://www.youtube.com/watch?v=v1",
              "stream_audio_url": "https://download.netslive.com/api/app/stream?type=audio&url=v1",
              "stream_video_url": "https://download.netslive.com/api/app/stream?type=video&url=v1"
            }
          ]
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ResolvedOnlineBatch.self, from: json)
        XCTAssertEqual(decoded.type, "playlist")
        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertEqual(decoded.items[0].index, 1)
    }
}
