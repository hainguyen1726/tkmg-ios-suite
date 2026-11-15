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
}
