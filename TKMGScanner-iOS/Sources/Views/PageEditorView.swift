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
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)

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

            VStack(spacing: 8) {
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

            HStack(spacing: 12) {
                Button {
                    rotationDegrees = (rotationDegrees + 90) % 360
                    refreshPreview()
                } label: {
                    Label("Xoay 90°", systemImage: "rotate.right")
                }
                .buttonStyle(.bordered)

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
                    Label("Tất cả trang", systemImage: "doc.on.doc")
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
                            rotationDegrees: rotationDegrees
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
        .navigationTitle("Chỉnh trang (Rust Core)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let p = page {
                mode = p.filterMode
                brightness = p.brightness
                contrast = p.contrast
                rotationDegrees = p.rotationDegrees
                if let orig = store.originalImage(for: p) {
                    sourcePreview = RustImageProcessor.normalizedAndRotated(image: orig, rotationDegrees: 0, maxEdgePx: 1100)
                    refreshPreview()
                }
            }
        }
    }

    private func refreshPreview() {
        guard let src = sourcePreview else { return }
        let m = mode
        let b = brightness
        let c = contrast
        let r = rotationDegrees
        Task.detached(priority: .userInitiated) {
            let out = RustImageProcessor.process(
                image: src,
                mode: m,
                brightnessOffset: b,
                contrastScale: c,
                rotationDegrees: r,
                maxEdgePx: 1100
            )
            await MainActor.run {
                previewImage = out
            }
        }
    }
}
