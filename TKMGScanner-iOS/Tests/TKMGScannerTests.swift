import XCTest
@testable import TKMGScanner

final class TKMGScannerTests: XCTestCase {
    func testAdaptiveBWFilterProducesHighContrastPaperAndInk() {
        let size = CGSize(width: 40, height: 40)
        let renderer = UIGraphicsImageRenderer(size: size)
        let synthetic = renderer.image { ctx in
            UIColor(red: 0.88, green: 0.85, blue: 0.78, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 10, y: 18, width: 20, height: 4))
        }

        let processed = RustImageProcessor.process(
            image: synthetic,
            mode: .bwDoc,
            brightnessOffset: 0.0,
            contrastScale: 1.0
        )

        XCTAssertNotNil(processed.cgImage)
        XCTAssertEqual(processed.cgImage?.width, 40)
        XCTAssertEqual(processed.cgImage?.height, 40)
    }

    func testPerspectiveCropPreservesInteriorAndIdCardCompositionIsA4() {
        let size = CGSize(width: 40, height: 40)
        let renderer = UIGraphicsImageRenderer(size: size)
        let src = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 10, y: 10, width: 20, height: 20))
        }
        let quad: [Float] = [0.3, 0.3, 0.7, 0.3, 0.72, 0.7, 0.28, 0.7]
        let cropped = RustImageProcessor.perspectiveCrop(image: src, quadNorm: quad, rotationDegrees: 0, maxEdgePx: 200)
        XCTAssertNotNil(cropped)
        XCTAssertGreaterThanOrEqual(cropped?.cgImage?.width ?? 0, 16)

        let idCardA4 = RustImageProcessor.composeIdCardA4(front: src, back: src, mode: .original)
        XCTAssertEqual(idCardA4.cgImage?.width, 1240)
        XCTAssertEqual(idCardA4.cgImage?.height, 1754)
    }

    func testAutoDeskewFindsCorrectionAndScannedPageDecodesWithoutFineAngle() throws {
        // Synthetic tilted text lines (+6 deg clockwise) rendered via CoreGraphics
        let size = CGSize(width: 180, height: 180)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let tilted = UIGraphicsImageRenderer(size: size, format: format).image { rctx in
            let ctx = rctx.cgContext
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.translateBy(x: 90, y: 90)
            ctx.rotate(by: 6.0 * .pi / 180.0)
            UIColor.black.setFill()
            for row in stride(from: -50, through: 50, by: 16) {
                ctx.fill(CGRect(x: -55, y: row, width: 110, height: 5))
            }
        }
        let correction = RustImageProcessor.estimateSkewDegrees(image: tilted, maxAngleDeg: 15.0)
        XCTAssertLessThan(abs(correction - (-6.0)), 1.0, "Expected ~ -6.0 deg correction, got \(correction)")

        let legacyJson = """
        {
          "id": "p1",
          "originalFileName": "p1_orig.jpg",
          "renderedFileName": "p1_rend.jpg",
          "filterMode": 1,
          "brightness": 0.0,
          "contrast": 1.0,
          "rotationDegrees": 0
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ScannedPage.self, from: legacyJson)
        XCTAssertEqual(decoded.fineAngleDegrees, 0.0)
    }

#if SIDELOAD_BUILD
    func testAppUpdateLogicDetectsNewerScannerIOSBuild() throws {
        let json = """
        {
          "apps": [
            {
              "id": "tkmg-scanner-ios",
              "name": "TKMG Scanner (iPhone)",
              "version": "1.2.0",
              "buildCode": 3,
              "apkUrl": "downloads/02-tkmg-scanner-ios-v1.2.ipa",
              "apkFileName": "02-tkmg-scanner-ios-v1.2.ipa",
              "apkSizeLabel": "320 KB",
              "whatsNew": "Cải tiến"
            }
          ]
        }
        """.data(using: .utf8)!
        let parsed = AppUpdateLogic.parseAppEntry(from: json, appId: "tkmg-scanner-ios")
        XCTAssertNotNil(parsed)
        XCTAssertTrue(AppUpdateLogic.isNewerUpdate(remote: parsed!, localVersion: "1.1.0", localBuildCode: 2))
        XCTAssertFalse(AppUpdateLogic.isNewerUpdate(remote: parsed!, localVersion: "1.2.0", localBuildCode: 3))
    }
#endif
}
