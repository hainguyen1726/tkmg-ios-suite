import PhotosUI
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ScanStore

    @State private var selectedFolderId = "all"
    @State private var searchQuery = ""
    @State private var sortOrder: DocumentSortOrder = .updatedDesc
    @State private var showCamera = false
    @State private var showIdCardComposer = false
    @State private var showNoCameraAlert = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var navigationPath = NavigationPath()

    private var visibleDocs: [ScannedDocument] {
        store.filteredDocuments(folderId: selectedFolderId, query: searchQuery, sort: sortOrder)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Folder Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.folders) { folder in
                            Button {
                                selectedFolderId = folder.id
                            } label: {
                                Label(folder.name, systemImage: folder.icon)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(selectedFolderId == folder.id ? Color.accentColor : Color.white.opacity(0.08))
                                    .foregroundColor(selectedFolderId == folder.id ? .black : .primary)
                                    .clipShape(Capsule())
                            }
                        }

                        Button {
                            newFolderName = ""
                            showNewFolderAlert = true
                        } label: {
                            Label("Mới", systemImage: "folder.badge.plus")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                if visibleDocs.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "doc.viewfinder")
                            .font(.system(size: 52))
                            .foregroundColor(.accentColor)
                        Text("Chưa có tài liệu nào")
                            .font(.headline)
                        Text("Nhấn \"Quét ngay\" để chụp hợp đồng, CCCD, hóa đơn với AI tự bắt viền & bộ lọc Rust ARM64.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        HStack(spacing: 12) {
                            Button {
                                startCameraScan()
                            } label: {
                                Label("Quét ngay", systemImage: "camera.viewfinder")
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.borderedProminent)

                            PhotosPicker(
                                selection: $selectedPhotoItems,
                                maxSelectionCount: 20,
                                matching: .images
                            ) {
                                Label("Chọn ảnh", systemImage: "photo.on.rectangle")
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.bordered)
                        }
                        Button {
                            showIdCardComposer = true
                        } label: {
                            Label("Ghép CCCD 2 mặt vào A4", systemImage: "person.text.rectangle.fill")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(visibleDocs) { doc in
                            NavigationLink(value: doc.id) {
                                DocumentRowView(doc: doc)
                                    .environmentObject(store)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.deleteDocument(doc)
                                } label: {
                                    Label("Xóa", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("TKMG Scanner")
            .searchable(text: $searchQuery, prompt: "Tìm hợp đồng, giấy tờ...")
            .navigationDestination(for: String.self) { docId in
                DocumentDetailView(documentID: docId)
                    .environmentObject(store)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Sắp xếp", selection: $sortOrder) {
                            ForEach(DocumentSortOrder.allCases) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        Picker("Bộ lọc mặc định", selection: $store.defaultFilter) {
                            ForEach(ScanFilterMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showIdCardComposer = true
                    } label: {
                        Image(systemName: "person.text.rectangle")
                    }

                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 20,
                        matching: .images
                    ) {
                        Image(systemName: "photo.badge.plus")
                    }

                    Button {
                        startCameraScan()
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.title3)
                    }
                }
            }
            .overlay {
                if store.isProcessing {
                    ZStack {
                        Color.black.opacity(0.45).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.large)
                            Text("Đang xử lý ảnh Rust ARM64...")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .sheet(isPresented: $showIdCardComposer) {
                IdCardComposerView(onCreated: { doc in
                    navigationPath.append(doc.id)
                })
                .environmentObject(store)
            }
            .fullScreenCover(isPresented: $showCamera) {
                DocumentCameraWrapper(
                    onComplete: { images in
                        showCamera = false
                        Task {
                            if let doc = await store.addScannedDocument(images: images, folderId: selectedFolderId) {
                                navigationPath.append(doc.id)
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
            .onChange(of: selectedPhotoItems) { newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    var loaded: [UIImage] = []
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let uiImg = UIImage(data: data) {
                            loaded.append(uiImg)
                        }
                    }
                    selectedPhotoItems = []
                    if let doc = await store.addScannedDocument(images: loaded, folderId: selectedFolderId) {
                        navigationPath.append(doc.id)
                    }
                }
            }
            .alert("Thiết bị không hỗ trợ Camera Scan", isPresented: $showNoCameraAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Trình quét VisionKit cần Camera thật trên iPhone. Bạn vẫn có thể chọn ảnh từ Thư viện ảnh.")
            }
            .alert("Tạo thư mục mới", isPresented: $showNewFolderAlert) {
                TextField("Tên thư mục", text: $newFolderName)
                Button("Tạo") {
                    store.createFolder(name: newFolderName)
                }
                Button("Hủy", role: .cancel) {}
            }
            .alert("Thông báo", isPresented: Binding(
                get: { store.toastMessage != nil },
                set: { if !$0 { store.toastMessage = nil } }
            )) {
                Button("OK", role: .cancel) { store.toastMessage = nil }
            } message: {
                Text(store.toastMessage ?? "")
            }
        }
    }

    private func startCameraScan() {
        if DocumentCameraWrapper.isSupported {
            showCamera = true
        } else {
            showNoCameraAlert = true
        }
    }
}

struct DocumentRowView: View {
    @EnvironmentObject var store: ScanStore
    let doc: ScannedDocument

    var body: some View {
        HStack(spacing: 12) {
            if let first = doc.pages.first, let thumb = store.renderedImage(for: first) {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
            } else {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 54, height: 70)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(doc.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label("\(doc.pages.count) trang", systemImage: "doc.on.doc")
                    Text("•")
                    Text(Date(timeIntervalSince1970: doc.updatedAt), style: .date)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
