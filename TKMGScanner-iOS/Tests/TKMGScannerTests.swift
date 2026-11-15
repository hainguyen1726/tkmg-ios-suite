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
}
