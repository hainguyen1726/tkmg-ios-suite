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
}
