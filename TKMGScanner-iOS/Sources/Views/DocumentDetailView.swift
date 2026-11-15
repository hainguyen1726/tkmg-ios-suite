import PhotosUI
import SwiftUI

struct DocumentDetailView: View {
    @EnvironmentObject var store: ScanStore
    let documentID: String

    @State private var showCameraAdd = false
    @State private var showIdCardComposer = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showExportSheet = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var shareURLs: [URL] = []

    private var document: ScannedDocument? {
        store.documents.first { $0.id == documentID }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        Group {
            if let doc = document {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(doc.pages.enumerated()), id: \.element.id) { index, page in
                            NavigationLink {
                                PageEditorView(documentID: doc.id, pageID: page.id)
                                    .environmentObject(store)
                            } label: {
                                VStack(spacing: 6) {
                                    if let img = store.renderedImage(for: page) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 190)
                                            .background(Color.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }

                                    HStack {
                                        Text("Trang \(index + 1) • \(page.filterMode.shortLabel)")
                                            .font(.caption.weight(.medium))
                                            .foregroundColor(.primary)
                                        Spacer()
                                        if index > 0 {
                                            Button {
                                                store.movePage(documentID: doc.id, fromIndex: index, delta: -1)
                                            } label: {
                                                Image(systemName: "arrow.left.circle")
                                            }
                                        }
                                        if index + 1 < doc.pages.count {
                                            Button {
                                                store.movePage(documentID: doc.id, fromIndex: index, delta: 1)
                                            } label: {
                                                Image(systemName: "arrow.right.circle")
                                            }
                                        }
                                    }
                                    .font(.caption)
                                }
                                .padding(8)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.deletePage(documentID: doc.id, pageID: page.id)
                                } label: {
                                    Label("Xóa trang này", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding()
                }
                .navigationTitle(doc.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                renameText = doc.title
                                showRenameAlert = true
                            } label: {
                                Label("Đổi tên tài liệu", systemImage: "pencil")
                            }

                            Menu("Chuyển thư mục") {
                                ForEach(store.folders.filter { $0.id != "all" }) { folder in
                                    Button(folder.name) {
                                        store.moveDocumentFolder(documentID: doc.id, folderId: folder.id)
                                    }
                                }
                            }

                            Button {
                                showIdCardComposer = true
                            } label: {
                                Label("Ghép CCCD 2 mặt (A4)", systemImage: "person.text.rectangle")
                            }

                            Button {
                                Task { await store.savePagesToPhotos(doc) }
                            } label: {
                                Label("Lưu tất cả ảnh JPEG vào Ảnh", systemImage: "square.and.arrow.down")
                            }

                            Button {
                                printDocument(doc)
                            } label: {
                                Label("In tài liệu (AirPrint)", systemImage: "printer")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }

                        if DocumentCameraWrapper.isSupported {
                            Button {
                                showCameraAdd = true
                            } label: {
                                Image(systemName: "plus.viewfinder")
                            }
                        }

                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: 15,
                            matching: .images
                        ) {
                            Image(systemName: "photo.badge.plus")
                        }

                        Button {
                            showExportSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                .fullScreenCover(isPresented: $showCameraAdd) {
                    DocumentCameraWrapper(
                        onComplete: { images in
                            showCameraAdd = false
                            Task {
                                _ = await store.addScannedDocument(images: images, intoDocumentID: doc.id)
                            }
                        },
                        onCancel: { showCameraAdd = false },
                        onError: { err in
                            showCameraAdd = false
                            store.toastMessage = "Lỗi camera: \(err.localizedDescription)"
                        }
                    )
                    .ignoresSafeArea()
                }
                .onChange(of: selectedPhotoItems) { newItems in
                    guard !newItems.isEmpty else { return }
                    Task {
                        var imgs: [UIImage] = []
                        for item in newItems {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let uiImg = UIImage(data: data) {
                                imgs.append(uiImg)
                            }
                        }
                        selectedPhotoItems = []
                        _ = await store.addScannedDocument(images: imgs, intoDocumentID: doc.id)
                    }
                }
                .sheet(isPresented: $showIdCardComposer) {
                    IdCardComposerView(intoDocumentID: doc.id)
                        .environmentObject(store)
                }
                .sheet(isPresented: $showExportSheet) {
                    ExportPdfSheet(document: doc) { exportedURLs in
                        showExportSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            shareURLs = exportedURLs
                        }
                    }
                    .environmentObject(store)
                }
                .sheet(isPresented: Binding(
                    get: { !shareURLs.isEmpty },
                    set: { if !$0 { shareURLs = [] } }
                )) {
                    if !shareURLs.isEmpty {
                        ShareSheet(items: shareURLs)
                    }
                }
                .alert("Đổi tên tài liệu", isPresented: $showRenameAlert) {
                    TextField("Tên mới", text: $renameText)
                    Button("Lưu") {
                        store.renameDocument(documentID: doc.id, newTitle: renameText)
                    }
                    Button("Hủy", role: .cancel) {}
                }
            } else {
                Text("Không tìm thấy tài liệu").foregroundColor(.secondary)
            }
        }
    }

    private func printDocument(_ doc: ScannedDocument) {
        let images = doc.pages.compactMap { store.renderedImage(for: $0) }
        guard !images.isEmpty,
              let pdfURL = try? PdfExporter.exportPDF(
                  pageImages: images,
                  fileName: doc.title,
                  pageSize: .a4,
                  quality: .high
              ) else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = doc.title
        controller.printInfo = info
        controller.printingItem = pdfURL
        controller.present(animated: true)
    }
}

struct ExportPdfSheet: View {
    @EnvironmentObject var store: ScanStore
    @Environment(\.dismiss) var dismiss
    let document: ScannedDocument
    var onExported: ([URL]) -> Void

    @State private var exportMode: DocumentExportMode = .pdf
    @State private var pageSize: PdfPageSize = .a4
    @State private var quality: PdfQuality = .standard
    @State private var imageFormat: ImageExportFormat = .jpeg
    @State private var asLongImage = false
    @State private var selectedPageIDs: Set<String> = []
    @State private var isExporting = false

    private var selectedImages: [UIImage] {
        let chosen = document.pages.filter { selectedPageIDs.isEmpty || selectedPageIDs.contains($0.id) }
        return chosen.compactMap { store.renderedImage(for: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if document.pages.count > 1 {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(document.pages.enumerated()), id: \.element.id) { idx, page in
                                    let selected = selectedPageIDs.contains(page.id)
                                    Button {
                                        if selected && selectedPageIDs.count > 1 {
                                            selectedPageIDs.remove(page.id)
                                        } else {
                                            selectedPageIDs.insert(page.id)
                                        }
                                    } label: {
                                        Text("Trang \(idx + 1)")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(selected ? Color.accentColor : Color.gray.opacity(0.2))
                                            .foregroundColor(selected ? .black : .primary)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        HStack {
                            Text("Chọn trang (\(selectedPageIDs.count)/\(document.pages.count))")
                            Spacer()
                            Button(selectedPageIDs.count == document.pages.count ? "Chỉ giữ Tr.1" : "Chọn tất cả") {
                                if selectedPageIDs.count == document.pages.count, let first = document.pages.first {
                                    selectedPageIDs = [first.id]
                                } else {
                                    selectedPageIDs = Set(document.pages.map { $0.id })
                                }
                            }
                            .font(.caption)
                        }
                    }
                }

                Section("Định dạng xuất") {
                    Picker("Chế độ", selection: $exportMode) {
                        ForEach(DocumentExportMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if exportMode == .pdf {
                    Section("Khổ trang PDF") {
                        Picker("Khổ giấy", selection: $pageSize) {
                            ForEach(PdfPageSize.allCases) { size in
                                VStack(alignment: .leading) {
                                    Text(size.rawValue)
                                    Text(size.subtitle).font(.caption).foregroundColor(.secondary)
                                }.tag(size)
                            }
                        }
                        .pickerStyle(.inline)
                    }

                    Section("Chất lượng & Dung lượng") {
                        Picker("Mức nén", selection: $quality) {
                            ForEach(PdfQuality.allCases) { q in
                                Text(q.rawValue).tag(q)
                            }
                        }
                        .pickerStyle(.inline)
                    }

                    Section {
                        Button {
                            runPdfExport()
                        } label: {
                            HStack {
                                Spacer()
                                if isExporting {
                                    ProgressView()
                                } else {
                                    Label("Xuất PDF & Chia sẻ (\(selectedImages.count) trang)", systemImage: "square.and.arrow.up")
                                        .fontWeight(.bold)
                                }
                                Spacer()
                            }
                        }
                        .disabled(isExporting || selectedImages.isEmpty)
                    }
                } else {
                    Section("Tùy chọn file Ảnh") {
                        Picker("Định dạng ảnh", selection: $imageFormat) {
                            ForEach(ImageExportFormat.allCases) { fmt in
                                Text(fmt.rawValue).tag(fmt)
                            }
                        }
                        .pickerStyle(.inline)

                        if selectedImages.count > 1 {
                            Toggle("Ghép \(selectedImages.count) trang thành 1 Ảnh dài", isOn: $asLongImage)
                        }
                    }

                    Section {
                        Button {
                            runImageShareExport()
                        } label: {
                            HStack {
                                Spacer()
                                if isExporting {
                                    ProgressView()
                                } else {
                                    Label("Chia sẻ Ảnh / Lưu Tệp (Zalo, Files...)", systemImage: "square.and.arrow.up")
                                        .fontWeight(.bold)
                                }
                                Spacer()
                            }
                        }
                        .disabled(isExporting || selectedImages.isEmpty)

                        Button {
                            let imgs = selectedImages
                            let fmt = imageFormat
                            let longMode = asLongImage
                            Task {
                                await store.saveCustomImagesToPhotos(imgs, format: fmt, asLongImage: longMode)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Label("Lưu vào Thư viện Ảnh iPhone", systemImage: "photo.on.rectangle")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(isExporting || selectedImages.isEmpty)
                    }
                }
            }
            .navigationTitle("Xuất & Chia sẻ (Không Watermark)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Đóng") { dismiss() }
            }
            .onAppear {
                if selectedPageIDs.isEmpty {
                    selectedPageIDs = Set(document.pages.map { $0.id })
                }
            }
        }
    }

    private func runPdfExport() {
        isExporting = true
        let images = selectedImages
        let title = document.title
        let size = pageSize
        let qual = quality
        Task.detached(priority: .userInitiated) {
            let url = try? PdfExporter.exportPDF(pageImages: images, fileName: title, pageSize: size, quality: qual)
            await MainActor.run {
                isExporting = false
                if let url {
                    onExported([url])
                }
            }
        }
    }

    private func runImageShareExport() {
        isExporting = true
        let images = selectedImages
        let title = document.title
        let fmt = imageFormat
        let longMode = asLongImage
        Task.detached(priority: .userInitiated) {
            let urls = (try? PdfExporter.exportImageFiles(
                pageImages: images,
                fileName: title,
                format: fmt,
                asLongImage: longMode
            )) ?? []
            await MainActor.run {
                isExporting = false
                if !urls.isEmpty {
                    onExported(urls)
                }
            }
        }
    }
}
