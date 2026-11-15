import Foundation
import UIKit

enum PdfExporter {
    static func exportPDF(
        pageImages: [UIImage],
        fileName: String,
        pageSize: PdfPageSize,
        quality: PdfQuality
    ) throws -> URL {
        let safeName = fileName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (safeName.isEmpty ? "TKMG_Scan" : safeName) + ".pdf"
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent(finalName)

        let a4Bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "TKMG Scanner (Rust ARM64 Core)",
            kCGPDFContextTitle as String: safeName
        ]

        let firstPageBounds: CGRect
        if pageSize == .a4 || pageImages.isEmpty {
            firstPageBounds = a4Bounds
        } else {
            let s = pageImages[0].size
            let maxW: CGFloat = 1200
            let scale = s.width > maxW ? maxW / s.width : 1.0
            firstPageBounds = CGRect(x: 0, y: 0, width: max(100, s.width * scale), height: max(100, s.height * scale))
        }

        let renderer = UIGraphicsPDFRenderer(bounds: firstPageBounds, format: format)
        let data = renderer.pdfData { ctx in
            for rawImg in pageImages {
                let prepared = prepareJPEGImage(rawImg, maxEdge: quality.maxEdgePx, compression: quality.jpegCompression)
                let imgSize = prepared.size

                let bounds: CGRect
                if pageSize == .a4 {
                    bounds = a4Bounds
                } else {
                    let maxW: CGFloat = 1200
                    let scale = imgSize.width > maxW ? maxW / imgSize.width : 1.0
                    bounds = CGRect(x: 0, y: 0, width: max(100, imgSize.width * scale), height: max(100, imgSize.height * scale))
                }

                ctx.beginPage(withBounds: bounds, pageInfo: [:])
                UIColor.white.setFill()
                ctx.cgContext.fill(bounds)

                let margin: CGFloat = pageSize == .a4 ? 18 : 0
                let targetRect = bounds.insetBy(dx: margin, dy: margin)
                let drawRect = aspectFitRect(imageSize: imgSize, inside: targetRect)
                prepared.draw(in: drawRect)
            }
        }

        try data.write(to: outURL, options: .atomic)
        return outURL
    }

    static func exportImageFiles(
        pageImages: [UIImage],
        fileName: String,
        format: ImageExportFormat,
        asLongImage: Bool
    ) throws -> [URL] {
        let safeBase = fileName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = safeBase.isEmpty ? "TKMG_Scan" : safeBase
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tkmg_img_exports", isDirectory: true)
        try? FileManager.default.removeItem(at: tmpDir)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        func encodeImage(_ img: UIImage) -> Data? {
            switch format {
            case .jpeg: return img.jpegData(compressionQuality: 0.92)
            case .png: return img.pngData()
            }
        }

        if asLongImage, pageImages.count > 1, let longImg = RustImageProcessor.composeLongImage(pages: pageImages),
           let data = encodeImage(longImg) {
            let url = tmpDir.appendingPathComponent("\(prefix)_Dai.\(format.fileExtension)")
            try data.write(to: url, options: .atomic)
            return [url]
        }

        var urls: [URL] = []
        for (idx, img) in pageImages.enumerated() {
            if let data = encodeImage(img) {
                let url = tmpDir.appendingPathComponent(String(format: "%@_Trang_%02d.%@", prefix, idx + 1, format.fileExtension))
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
        }
        return urls
    }

    private static func prepareJPEGImage(_ image: UIImage, maxEdge: CGFloat, compression: CGFloat) -> UIImage {
        let scaled = RustImageProcessor.normalizedAndRotated(image: image, rotationDegrees: 0, maxEdgePx: maxEdge)
        guard let jpegData = scaled.jpegData(compressionQuality: compression),
              let redecoded = UIImage(data: jpegData) else {
            return scaled
        }
        return redecoded
    }

    private static func aspectFitRect(imageSize: CGSize, inside container: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return container }
        let ratio = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * ratio
        let h = imageSize.height * ratio
        return CGRect(
            x: container.midX - w / 2,
            y: container.midY - h / 2,
            width: w,
            height: h
        )
    }
}
