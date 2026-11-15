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

    static func perspectiveCrop(
        image: UIImage,
        quadNorm: [Float],
        rotationDegrees: Int = 0,
        maxEdgePx: CGFloat = 2400
    ) -> UIImage? {
        guard quadNorm.count >= 8 else { return nil }
        let oriented = normalizedAndRotated(image: image, rotationDegrees: rotationDegrees, maxEdgePx: maxEdgePx)
        guard let cgImage = oriented.cgImage else { return nil }

        let sw = cgImage.width
        let sh = cgImage.height
        guard sw >= 2, sh >= 2 else { return nil }

        var srcPixels = [UInt32](repeating: 0, count: sw * sh)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        let drawn = srcPixels.withUnsafeMutableBufferPointer { buf -> Bool in
            guard let base = buf.baseAddress,
                  let ctx = CGContext(
                      data: base,
                      width: sw,
                      height: sh,
                      bitsPerComponent: 8,
                      bytesPerRow: sw * 4,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo
                  ) else {
                return false
            }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: sw, height: sh))
            return true
        }
        guard drawn else { return nil }

        var outW: Int32 = 0
        var outH: Int32 = 0
        let estOk = quadNorm.withUnsafeBufferPointer { qPtr -> Int32 in
            guard let baseQ = qPtr.baseAddress else { return 0 }
            return tkmg_estimate_quad_size(Int32(sw), Int32(sh), baseQ, Int32(maxEdgePx), &outW, &outH)
        }
        guard estOk == 1, outW >= 2, outH >= 2 else { return nil }

        let dw = Int(outW)
        let dh = Int(outH)
        var dstPixels = [UInt32](repeating: 0, count: dw * dh)

        let warpOk = srcPixels.withUnsafeBufferPointer { srcBuf in
            dstPixels.withUnsafeMutableBufferPointer { dstBuf in
                quadNorm.withUnsafeBufferPointer { qBuf -> Int32 in
                    guard let s = srcBuf.baseAddress, let d = dstBuf.baseAddress, let q = qBuf.baseAddress else {
                        return 0
                    }
                    return tkmg_perspective_warp_argb(s, Int32(sw), Int32(sh), q, d, outW, outH)
                }
            }
        }
        guard warpOk == 1 else { return nil }

        return dstPixels.withUnsafeMutableBufferPointer { dstBuf -> UIImage? in
            guard let base = dstBuf.baseAddress,
                  let ctx = CGContext(
                      data: base,
                      width: dw,
                      height: dh,
                      bitsPerComponent: 8,
                      bytesPerRow: dw * 4,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo
                  ),
                  let outCG = ctx.makeImage() else {
                return nil
            }
            return UIImage(cgImage: outCG, scale: 1.0, orientation: .up)
        }
    }

    static func composeIdCardA4(front: UIImage, back: UIImage, mode: ScanFilterMode) -> UIImage {
        let a4Size = CGSize(width: 1240, height: 1754)
        let cleanFront = process(image: front, mode: mode, brightnessOffset: 0, contrastScale: 1.0, maxEdgePx: 1400)
        let cleanBack = process(image: back, mode: mode, brightnessOffset: 0, contrastScale: 1.0, maxEdgePx: 1400)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: a4Size, format: format)

        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: a4Size))

            let slotW: CGFloat = 860
            let slotH: CGFloat = 560
            let slotX = (a4Size.width - slotW) / 2

            func drawCard(_ img: UIImage, topY: CGFloat) {
                let s = img.size
                guard s.width > 0, s.height > 0 else { return }
                let ratio = min(slotW / s.width, slotH / s.height)
                let w = s.width * ratio
                let h = s.height * ratio
                let rect = CGRect(
                    x: slotX + (slotW - w) / 2,
                    y: topY + (slotH - h) / 2,
                    width: w,
                    height: h
                )
                img.draw(in: rect)
                UIColor(red: 0.796, green: 0.835, blue: 0.882, alpha: 1.0).setStroke()
                let border = UIBezierPath(rect: rect)
                border.lineWidth = 2
                border.stroke()
            }

            drawCard(cleanFront, topY: 220)
            drawCard(cleanBack, topY: 960)
        }
    }

    static func composeLongImage(pages: [UIImage]) -> UIImage? {
        let subset = Array(pages.prefix(15))
        guard !subset.isEmpty else { return nil }
        let targetW: CGFloat = 1360
        let gap: CGFloat = 14

        var heights: [CGFloat] = []
        var totalH: CGFloat = 0
        for (idx, img) in subset.enumerated() {
            let s = img.size
            guard s.width > 0, s.height > 0 else {
                heights.append(0)
                continue
            }
            let h = floor(s.height * (targetW / s.width))
            heights.append(h)
            totalH += h
            if idx < subset.count - 1 { totalH += gap }
        }
        let clampedH = max(16, min(20000, totalH))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetW, height: clampedH), format: format)

        return renderer.image { ctx in
            UIColor(red: 0.886, green: 0.910, blue: 0.941, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: targetW, height: clampedH)))

            var y: CGFloat = 0
            for (idx, img) in subset.enumerated() {
                let h = heights[idx]
                if h > 0 && y + h <= clampedH {
                    img.draw(in: CGRect(x: 0, y: y, width: targetW, height: h))
                }
                y += h + gap
            }
        }
    }
}
