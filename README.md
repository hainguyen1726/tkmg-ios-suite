# TKMG Mobile Suite — Phiên bản iOS (iPhone / iPad)

Bộ đôi ứng dụng **sạch quảng cáo 100%** được viết bằng **SwiftUI Native + Lõi xử lý Rust ARM64 (`libtkmg_core.a`)**:

1. **TKMG Player (`com.tkmg.player`)**
   - Đọc file & thư mục nhạc MP3 / Video trực tiếp từ **Tệp (Files)** & iCloud Drive (Security-Scoped Bookmarks).
   - Sắp xếp tự nhiên theo đúng số tập (`Tập 1`, `Tập 2`... `Tập 10`) qua lõi **Rust ARM64**.
   - Phát nền tắt màn hình (`AVFoundation` + Lock Screen Controls), hẹn giờ tắt, nhớ vị trí nghe dở từng file, đổi tên chuẩn hóa hàng loạt & Playlist riêng.

2. **TKMG Scanner (`com.tkmg.scanner`)**
   - Quét tài liệu thông minh qua **Apple VisionKit** (`VNDocumentCameraViewController`): tự bắt viền giấy, tự chụp, nắn phối cảnh 4 góc.
   - Hậu kỳ CamScanner chạy trên lõi **Rust ARM64**: *Magic Color* (giữ dấu đỏ), *Đen Trắng (B&W Adaptive)*, *Thang Xám*, *Siêu Nét*, chỉnh sáng/tương phản/xoay 90°.
   - Gộp nhiều trang, sắp xếp trang, xuất PDF sạch không watermark (A4 / khổ gốc, 3 mức nén), lưu JPEG vào Ảnh, chia sẻ Zalo/AirDrop hoặc In AirPrint.

---

## Tự động biên dịch `.ipa` bằng GitHub Actions (không cần máy Mac)

1. Tạo một repository trên GitHub (ví dụ `hainguyen1726/tkmg-ios-suite`) và push thư mục này lên nhánh `main`.
2. Vào tab **Actions -> Build TKMG iOS Apps**, workflow trên `macos-latest` sẽ tự động:
   - Biên dịch `tkmg-rust-core` sang `libtkmg_core.a` (`aarch64-apple-ios` & simulator).
   - Chạy unit test cả Rust và Swift (`XCTest`).
   - Đóng gói ra 2 file cài đặt: `01-tkmg-player-ios-v1.0.ipa` và `02-tkmg-scanner-ios-v1.0.ipa` trong mục **Artifacts** (hoặc **Releases** khi gắn tag `v1.0.0`).

## Cách cài `.ipa` lên iPhone
- **Không cần tài khoản Developer trả phí ($99/năm):** tải `.ipa` về máy tính, cài lên iPhone qua **Sideloadly**, **AltStore**, hoặc **SideStore** bằng Apple ID thường (SideStore tự gia hạn qua Wi-Fi mỗi 7 ngày ngay trên iPhone).
- **Có máy Mac / Apple Developer:** mở `.xcodeproj` sinh bởi `xcodegen generate` để ký và chạy trực tiếp hoặc đẩy TestFlight.

---
*Ủng hộ tùy tâm (Donate): MB Bank - `0964023333` - NGUYEN MINH HAI | Góp ý Zalo: `0964023333` | Web: https://mobile-app.netslive.com*
