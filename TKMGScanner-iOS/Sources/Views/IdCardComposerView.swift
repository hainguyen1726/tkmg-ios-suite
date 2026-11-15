import PhotosUI
import SwiftUI

struct IdCardComposerView: View {
    @EnvironmentObject var store: ScanStore
    @Environment(\.dismiss) var dismiss
    var intoDocumentID: String? = nil
    var onCreated: ((ScannedDocument) -> Void)? = nil

    @State private var frontImage: UIImage?
    @State private var backImage: UIImage?
    @State private var filterMode: ScanFilterMode = .magicColor
    @State private var captureFrontSlot = true
    @State private var showCamera = false
    @State private var frontPickerItem: PhotosPickerItem?
    @State private var backPickerItem: PhotosPickerItem?

    private let filters: [ScanFilterMode] = [.magicColor, .original, .superSharp, .bwDoc]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Chụp hoặc chọn ảnh Mặt trước & Mặt sau. Hệ thống sẽ căn giữa cân đối trên 1 trang A4 sắc nét.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("1. Mặt trước") {
                    slotPreview(frontImage)
                    HStack(spacing: 12) {
                        if DocumentCameraWrapper.isSupported {
                            Button {
                                captureFrontSlot = true
                                showCamera = true
                            } label: {
                                Label("Chụp Camera", systemImage: "camera.viewfinder")
                            }
                            .buttonStyle(.bordered)
                        }
                        PhotosPicker(selection: $frontPickerItem, matching: .images) {
                            Label("Chọn ảnh", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section("2. Mặt sau") {
                    slotPreview(backImage)
                    HStack(spacing: 12) {
                        if DocumentCameraWrapper.isSupported {
                            Button {
                                captureFrontSlot = false
                                showCamera = true
                            } label: {
                                Label("Chụp Camera", systemImage: "camera.viewfinder")
                            }
                            .buttonStyle(.bordered)
                        }
                        PhotosPicker(selection: $backPickerItem, matching: .images) {
                            Label("Chọn ảnh", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section("Chế độ lọc màu") {
                    Picker("Bộ lọc", selection: $filterMode) {
                        ForEach(filters) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button {
                        guard let f = frontImage, let b = backImage else { return }
                        Task {
                            if let doc = await store.addIdCardA4Document(
                                front: f,
                                back: b,
                                mode: filterMode,
                                intoDocumentID: intoDocumentID
                            ) {
                                onCreated?(doc)
                            }
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Ghép thành trang A4", systemImage: "person.text.rectangle.fill")
                                .fontWeight(.bold)
                            Spacer()
                        }
                    }
                    .disabled(frontImage == nil || backImage == nil || store.isProcessing)
                }
            }
            .navigationTitle("Ghép CCCD 2 mặt (A4)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Đóng") { dismiss() }
            }
            .fullScreenCover(isPresented: $showCamera) {
                DocumentCameraWrapper(
                    onComplete: { images in
                        showCamera = false
                        if let first = images.first {
                            if captureFrontSlot {
                                frontImage = first
                            } else {
                                backImage = first
                            }
                        }
                    },
                    onCancel: { showCamera = false },
                    onError: { err in
                        showCamera = false
                        store.toastMessage = "Lỗi camera: \(err.localizedDescription)"
                    }
                )
                .ignoresSafeArea()
            }
            .onChange(of: frontPickerItem) { newItem in
                loadPickedImage(newItem) { frontImage = $0; frontPickerItem = nil }
            }
            .onChange(of: backPickerItem) { newItem in
                loadPickedImage(newItem) { backImage = $0; backPickerItem = nil }
            }
        }
    }

    @ViewBuilder
    private func slotPreview(_ img: UIImage?) -> some View {
        if let img {
            HStack {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer()
                Label("Đã chọn", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.green)
            }
        }
    }

    private func loadPickedImage(_ item: PhotosPickerItem?, completion: @escaping (UIImage) -> Void) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                await MainActor.run {
                    completion(img)
                }
            }
        }
    }
}
