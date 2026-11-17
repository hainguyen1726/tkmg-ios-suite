import SwiftUI

struct PageEditorView: View {
    @EnvironmentObject var store: ScanStore
    @Environment(\.dismiss) var dismiss
    let documentID: String
    let pageID: String

    @State private var mode: ScanFilterMode = .magicColor
    @State private var brightness: Float = 0.0
    @State private var contrast: Float = 1.0
    @State private var rotationDegrees: Int = 0
    @State private var fineAngleDegrees: Float = 0.0
    @State private var showGrid = false
    @State private var isAdjustingSkew = false
    @State private var isAutoAligning = false
    @State private var isCropping = false
    @State private var quadPoints: [CGPoint] = [
        CGPoint(x: 0.06, y: 0.06),
        CGPoint(x: 0.94, y: 0.06),
        CGPoint(x: 0.94, y: 0.94),
        CGPoint(x: 0.06, y: 0.94)
    ]
    @State private var activeCornerIdx: Int? = nil
    @State private var previewImage: UIImage?
    @State private var sourcePreview: UIImage?

    private var page: ScannedPage? {
        store.documents.first { $0.id == documentID }?.pages.first { $0.id == pageID }
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Color.black.opacity(0.85)
                if let previewImage {
                    GeometryReader { geo in
                        let drawRect = aspectFitRect(imageSize: previewImage.size, container: geo.size.insetBy(12))
                        ZStack {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: drawRect.width, height: drawRect.height)
                                .position(x: drawRect.midX, y: drawRect.midY)

                            if (showGrid || isAdjustingSkew || isCropping) && drawRect.width > 10 && drawRect.height > 10 {
                                AlignmentGridOverlay(drawRect: drawRect)
                            }

                            if isCropping && drawRect.width > 10 && drawRect.height > 10 {
                                QuadCropOverlay(
                                    quadPoints: $quadPoints,
                                    activeCornerIdx: $activeCornerIdx,
                                    drawRect: drawRect
                                )
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)

            if isCropping {
                VStack(spacing: 10) {
                    Text("Kéo 4 chấm tròn vào 4 góc tờ giấy hoặc bấm Tự bắt viền rồi Áp dụng.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                detectPaperCorners()
                            } label: {
                                Label(isAutoAligning ? "Đang dò..." : "Tự bắt viền", systemImage: "viewfinder")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isAutoAligning)

                            Button("Đặt lại") {
                                quadPoints = [
                                    CGPoint(x: 0.06, y: 0.06),
                                    CGPoint(x: 0.94, y: 0.06),
                                    CGPoint(x: 0.94, y: 0.94),
                                    CGPoint(x: 0.06, y: 0.94)
                                ]
                            }
                            .buttonStyle(.bordered)

                            if let p = page, store.hasCropBackup(for: p) {
                                Button("Khôi phục gốc") {
                                    isCropping = false
                                    Task {
                                        await store.resetPerspectiveCrop(
                                            documentID: documentID,
                                            pageID: pageID,
                                            mode: mode,
                                            brightness: brightness,
                                            contrast: contrast
                                        )
                                        rotationDegrees = 0
                                        fineAngleDegrees = 0.0
                                        reloadOriginalSource()
                                    }
                                }
                                .buttonStyle(.bordered)
                            }

                            Button("Hủy") {
                                isCropping = false
                                refreshPreview()
                            }
                            .buttonStyle(.bordered)

                            Button("Áp dụng") {
                                let qFloat: [Float] = quadPoints.flatMap { [Float($0.x), Float($0.y)] }
                                isCropping = false
                                Task {
                                    await store.applyPerspectiveCrop(
                                        documentID: documentID,
                                        pageID: pageID,
                                        quadNorm: qFloat,
                                        rotationDegrees: rotationDegrees,
                                        fineAngleDegrees: fineAngleDegrees,
                                        mode: mode,
                                        brightness: brightness,
                                        contrast: contrast
                                    )
                                    rotationDegrees = 0
                                    fineAngleDegrees = 0.0
                                    reloadOriginalSource()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            } else {
                // Filter Strip
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ScanFilterMode.allCases) { f in
                            Button {
                                mode = f
                                refreshPreview()
                            } label: {
                                Text(f.label)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(mode == f ? Color.accentColor : Color.white.opacity(0.08))
                                    .foregroundColor(mode == f ? .black : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Căn nghiêng")
                            .font(.caption)
                            .frame(width: 72, alignment: .leading)
                        Slider(value: $fineAngleDegrees, in: -15.0...15.0, step: 0.5, onEditingChanged: { editing in
                            isAdjustingSkew = editing
                            if !editing { refreshPreview() }
                        })
                        Text(String(format: "%.1f°", fineAngleDegrees))
                            .font(.caption.monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                        if abs(fineAngleDegrees) >= 0.1 {
                            Button("0°") {
                                fineAngleDegrees = 0.0
                                refreshPreview()
                            }
                            .font(.caption2.weight(.semibold))
                            .buttonStyle(.bordered)
                        }
                        Button {
                            runAutoDeskew()
                        } label: {
                            Label(isAutoAligning ? "..." : "Tự thẳng", systemImage: "level")
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .disabled(isAutoAligning)
                    }
                    HStack {
                        Text("Độ sáng").font(.caption).frame(width: 72, alignment: .leading)
                        Slider(value: $brightness, in: -0.3...0.3, onEditingChanged: { editing in
                            if !editing { refreshPreview() }
                        })
                    }
                    HStack {
                        Text("Tương phản").font(.caption).frame(width: 72, alignment: .leading)
                        Slider(value: $contrast, in: 0.6...1.8, onEditingChanged: { editing in
                            if !editing { refreshPreview() }
                        })
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 8) {
                    Button {
                        isCropping = true
                        refreshPreview()
                    } label: {
                        Label("Cắt góc", systemImage: "crop")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        rotationDegrees = (rotationDegrees + 90) % 360
                        refreshPreview()
                    } label: {
                        Image(systemName: "rotate.right")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Xoay 90 độ")

                    Button {
                        showGrid.toggle()
                    } label: {
                        Image(systemName: "grid")
                    }
                    .buttonStyle(.bordered)
                    .tint(showGrid ? .accentColor : .secondary)
                    .accessibilityLabel("Bật tắt lưới căn chỉnh")

                    Button {
                        Task {
                            await store.applyStyleToAllPages(
                                documentID: documentID,
                                mode: mode,
                                brightness: brightness,
                                contrast: contrast
                            )
                            dismiss()
                        }
                    } label: {
                        Label("Tất cả", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        Task {
                            await store.updatePage(
                                documentID: documentID,
                                pageID: pageID,
                                mode: mode,
                                brightness: brightness,
                                contrast: contrast,
                                rotationDegrees: rotationDegrees,
                                fineAngleDegrees: fineAngleDegrees
                            )
                            dismiss()
                        }
                    } label: {
                        Text("Lưu trang")
                            .fontWeight(.bold)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle(isCropping ? "Cắt nắn 4 góc" : "Chỉnh trang (Rust Core)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let p = page {
                mode = p.filterMode
                brightness = p.brightness
                contrast = p.contrast
                rotationDegrees = p.rotationDegrees
                fineAngleDegrees = p.fineAngleDegrees
                reloadOriginalSource()
            }
        }
    }

    private func runAutoDeskew() {
        guard let src = sourcePreview else { return }
        let rot = rotationDegrees
        isAutoAligning = true
        Task.detached(priority: .userInitiated) {
            let suggested = RustImageProcessor.estimateSkewDegrees(image: src, rotationDegrees: rot, maxAngleDeg: 15.0)
            await MainActor.run {
                isAutoAligning = false
                fineAngleDegrees = suggested
                showGrid = true
                refreshPreview()
                if abs(suggested) < 0.25 {
                    store.toastMessage = "Trang văn bản đã thẳng hàng"
                } else {
                    store.toastMessage = String(format: "Đã tự căn thẳng %.1f°", suggested)
                }
            }
        }
    }

    private func detectPaperCorners() {
        guard let src = sourcePreview else { return }
        let rot = rotationDegrees
        let fine = fineAngleDegrees
        isAutoAligning = true
        Task.detached(priority: .userInitiated) {
            let detected = RustImageProcessor.detectPaperQuad(in: src, rotationDegrees: rot, fineAngleDegrees: fine)
            await MainActor.run {
                isAutoAligning = false
                if let detected, detected.count == 4 {
                    quadPoints = detected
                } else {
                    store.toastMessage = "Không thấy rõ 4 mép giấy — hãy kéo 4 điểm góc thủ công"
                }
            }
        }
    }

    private func reloadOriginalSource() {
        if let p = page, let orig = store.originalImage(for: p) {
            sourcePreview = RustImageProcessor.normalizedAndRotated(image: orig, rotationDegrees: 0, maxEdgePx: 1100)
            refreshPreview()
        }
    }

    private func refreshPreview() {
        guard let src = sourcePreview else { return }
        let m = isCropping ? ScanFilterMode.original : mode
        let b: Float = isCropping ? 0.0 : brightness
        let c: Float = isCropping ? 1.0 : contrast
        let r = rotationDegrees
        let fa = fineAngleDegrees
        Task.detached(priority: .userInitiated) {
            let out = RustImageProcessor.process(
                image: src,
                mode: m,
                brightnessOffset: b,
                contrastScale: c,
                rotationDegrees: r,
                fineAngleDegrees: fa,
                maxEdgePx: 1100
            )
            await MainActor.run {
                previewImage = out
            }
        }
    }

    private func aspectFitRect(imageSize: CGSize, container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(x: 12, y: 12, width: max(1, container.width), height: max(1, container.height))
        }
        let ratio = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * ratio
        let h = imageSize.height * ratio
        return CGRect(
            x: 12 + (container.width - w) / 2,
            y: 12 + (container.height - h) / 2,
            width: w,
            height: h
        )
    }
}

private extension CGSize {
    func insetBy(_ inset: CGFloat) -> CGSize {
        CGSize(width: max(1, width - inset * 2), height: max(1, height - inset * 2))
    }
}

private struct AlignmentGridOverlay: View {
    let drawRect: CGRect

    var body: some View {
        Path { path in
            let divisions = 4
            for i in 1..<divisions {
                let t = CGFloat(i) / CGFloat(divisions)
                let vx = drawRect.minX + drawRect.width * t
                path.move(to: CGPoint(x: vx, y: drawRect.minY))
                path.addLine(to: CGPoint(x: vx, y: drawRect.maxY))

                let hy = drawRect.minY + drawRect.height * t
                path.move(to: CGPoint(x: drawRect.minX, y: hy))
                path.addLine(to: CGPoint(x: drawRect.maxX, y: hy))
            }
        }
        .stroke(Color.white.opacity(0.38), style: StrokeStyle(lineWidth: 0.9, dash: [4, 4]))
        .allowsHitTesting(false)
    }
}

private struct QuadCropOverlay: View {
    @Binding var quadPoints: [CGPoint]
    @Binding var activeCornerIdx: Int?
    let drawRect: CGRect

    var body: some View {
        ZStack {
            Path { path in
                let pts = screenPoints()
                guard pts.count == 4 else { return }
                path.move(to: pts[0])
                path.addLine(to: pts[1])
                path.addLine(to: pts[2])
                path.addLine(to: pts[3])
                path.closeSubpath()
            }
            .fill(Color.accentColor.opacity(0.16))

            Path { path in
                let pts = screenPoints()
                guard pts.count == 4 else { return }
                path.move(to: pts[0])
                path.addLine(to: pts[1])
                path.addLine(to: pts[2])
                path.addLine(to: pts[3])
                path.closeSubpath()
            }
            .stroke(Color.accentColor, lineWidth: 2.5)

            ForEach(0..<4, id: \.self) { idx in
                let pt = screenPoint(for: idx)
                Circle()
                    .fill(activeCornerIdx == idx ? Color.orange : Color.accentColor)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().fill(Color.white).frame(width: 10, height: 10))
                    .position(pt)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if activeCornerIdx == nil {
                        var best: Int? = nil
                        var bestDist: CGFloat = 52
                        for idx in 0..<4 {
                            let pt = screenPoint(for: idx)
                            let d = hypot(value.location.x - pt.x, value.location.y - pt.y)
                            if d < bestDist {
                                bestDist = d
                                best = idx
                            }
                        }
                        activeCornerIdx = best
                    }
                    if let idx = activeCornerIdx {
                        let nx = min(max((value.location.x - drawRect.minX) / drawRect.width, 0), 1)
                        let ny = min(max((value.location.y - drawRect.minY) / drawRect.height, 0), 1)
                        quadPoints[idx] = CGPoint(x: nx, y: ny)
                    }
                }
                .onEnded { _ in
                    activeCornerIdx = nil
                }
        )
    }

    private func screenPoint(for idx: Int) -> CGPoint {
        let p = quadPoints[idx]
        return CGPoint(
            x: drawRect.minX + p.x * drawRect.width,
            y: drawRect.minY + p.y * drawRect.height
        )
    }

    private func screenPoints() -> [CGPoint] {
        (0..<4).map { screenPoint(for: $0) }
    }
}
