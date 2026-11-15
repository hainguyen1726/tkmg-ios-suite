import CoreGraphics
import TkmgCore
import UIKit

enum RustImageProcessor {
    /// Normalizes EXIF orientation, rotates cleanly, applies Rust ARM64 filter on 0xAARRGGBB pixels.
    static func process(
        image: UIImage,
        mode: ScanFilterMode,
        brightnessOffset: Float,
        contrastScale: Float,
        rotationDegrees: Int = 0,
        maxEdgePx: CGFloat? = nil
    ) -> UIImage {
        let oriented = normalizedAndRotated(image: image, rotationDegrees: rotationDegrees, maxEdgePx: maxEdgePx)
        guard let cgImage = oriented.cgImage else { return oriented }

        if mode == .original && abs(brightnessOffset) < 0.005 && abs(contrastScale - 1.0) < 0.005 {
            return oriented
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return oriented }

        var pixels = [UInt32](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        return pixels.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress,
                  let ctx = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo
                  ) else {
                return oriented
            }

            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            tkmg_apply_document_filter_argb(
                base,
                Int32(width),
                Int32(height),
                Int32(mode.rawValue),
                brightnessOffset,
                contrastScale
            )

            guard let outCG = ctx.makeImage() else { return oriented }
            return UIImage(cgImage: outCG, scale: 1.0, orientation: .up)
        }
    }

    static func normalizedAndRotated(
        image: UIImage,
        rotationDegrees: Int,
        maxEdgePx: CGFloat?
    ) -> UIImage {
        let baseSize = image.size
        guard baseSize.width > 0, baseSize.height > 0 else { return image }

        var targetSize = baseSize
        if let maxEdgePx, max(baseSize.width, baseSize.height) > maxEdgePx {
            let ratio = maxEdgePx / max(baseSize.width, baseSize.height)
            targetSize = CGSize(width: floor(baseSize.width * ratio), height: floor(baseSize.height * ratio))
        }

        let normSteps = ((rotationDegrees % 360) + 360) % 360
        let swapAxes = normSteps == 90 || normSteps == 270
        let canvasSize = swapAxes
            ? CGSize(width: targetSize.height, height: targetSize.width)
            : targetSize

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { rendererCtx in
            let ctx = rendererCtx.cgContext
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: canvasSize))

            ctx.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)
            ctx.rotate(by: CGFloat(normSteps) * .pi / 180.0)
            image.draw(in: CGRect(
                x: -targetSize.width / 2,
                y: -targetSize.height / 2,
                width: targetSize.width,
                height: targetSize.height
            ))
        }
    }
}
