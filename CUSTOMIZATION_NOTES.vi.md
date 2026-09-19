# Bản chỉnh sửa Tizi Mod

Bản này giữ nguyên lõi chức năng của source gốc và đã được chỉnh theo thương hiệu **Tizi Mod**.

## Đã chỉnh sửa

### 1) Bật / tắt module trong Cài đặt
Có thể bật hoặc tắt riêng từng module sau:

- Tệp (Files)
- Patch
- Dọn dẹp (Cleaner)
- Hình nền (Wallpapers)
- Nhật ký (Logs)

Trang chủ và Cài đặt luôn được giữ để có thể bật lại các module đã tắt.
Trạng thái được lưu bằng `@AppStorage`.

### 2) Đổi thương hiệu giao diện
- Tên hiển thị app đổi thành **Tizi Mod**
- Đổi màu chủ đạo sang **xanh nước biển nhạt**
- Đã thay **icon app** theo ảnh bạn gửi
- Đã đổi một số chuỗi hiển thị trong giao diện từ `3105` sang `Tizi Mod`

## Những gì vẫn được giữ nguyên để tương thích

- **Bundle identifier** vẫn là `com.apple.mobile.MobileHouseArrest`
- **Định dạng patch `.3105`** vẫn được giữ nguyên
- Các phần nhận diện kỹ thuật nội bộ liên quan tới patch / import / exploit vẫn ưu tiên tương thích với source gốc

## File chính đã sửa

- `ThreeOneOSFive/views/DesignSystem.swift`
- `ThreeOneOSFive/ContentView.swift`
- `ThreeOneOSFive/views/AppDataBrowserView.swift`
- `ThreeOneOSFive/views/SettingsView.swift`
- `ThreeOneOSFive/helpers/Utils.swift`
- `ThreeOneOSFive/Info.plist`
- `ThreeOneOSFive/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- `ThreeOneOSFive/en.lproj/Localizable.strings`
- `ThreeOneOSFive/vi.lproj/Localizable.strings`
- `ThreeOneOSFive/zh-Hans.lproj/Localizable.strings`

## Lưu ý build

Để build và cài lên iPhone, bạn vẫn cần **macOS + Xcode**.
Nếu muốn, bước tiếp theo mình có thể giúp bạn:

- đổi tiếp tên project / scheme trong Xcode
- đổi splash / ảnh preview / README
- ẩn hẳn các module bạn không dùng
- tinh chỉnh giao diện Home theo phong cách riêng của bạn
