# Tizi Mod — bản có màn hình Key

Bản này giữ lõi chức năng của source gốc 3105, dùng thương hiệu **Tizi Mod** và bổ sung màn hình kích hoạt bằng key trước khi vào app.

## Giao diện key mới

- Màu nền xanh nước biển nhạt theo theme Tizi Mod.
- Logo Tizi Mod ở giữa phía trên.
- Tiêu đề **Nhập Key Kích Hoạt**.
- Ô nhập key có biểu tượng chìa khóa.
- Báo lỗi màu đỏ khi key sai.
- Nút **Kích hoạt** có trạng thái loading.
- Footer `Make By ©Tizi Mod`.
- Sau khi kích hoạt thành công, trạng thái được lưu để lần sau mở app đi thẳng vào giao diện chính.
- Trong Cài đặt có **Đăng xuất key** để quay lại màn hình kích hoạt.

## Key test hiện tại

Do chưa có API quản lý key thật, source đang có key test local:

```text
TIZI-MOD-DEMO
```

Key này chỉ để test giao diện. Không nên dùng cho bản phát hành thật.

## Gắn API key thật

Mở:

```text
ThreeOneOSFive/App.swift
```

Tìm:

```swift
enum ActivationConfiguration {
    static let apiEndpointString = ""
```

Điền URL HTTPS của API, ví dụ:

```swift
static let apiEndpointString = "https://domain-cua-ban.com/api/activate"
```

App sẽ POST JSON dạng:

```json
{
  "key": "TIZI-XXXX-XXXX",
  "deviceID": "...",
  "deviceModel": "...",
  "appVersion": "1.0.1"
}
```

API nên trả:

```json
{
  "success": true,
  "token": "token-cua-ban",
  "message": null
}
```

hoặc khi lỗi:

```json
{
  "success": false,
  "token": null,
  "message": "Key đã hết hạn"
}
```

## Build IPA trên GitHub Actions

Workflow đã có sẵn tại:

```text
.github/workflows/build-ipa.yml
```

Upload source lên GitHub rồi chạy **Actions → Build Tizi Mod IPA → Run workflow**.
Workflow hiện tạo IPA **unsigned**.

## Các phần vẫn giữ để tương thích

- Bundle ID: `com.apple.mobile.MobileHouseArrest`
- Định dạng patch: `.3105`
- Các phần kỹ thuật nội bộ liên quan tới patch/exploit giữ tương thích với source gốc.


## Giao diện 3 tab (bản mới)
- Thanh điều hướng chỉ còn: **Trang chủ / Patch / Next DNS**.
- Các module Files, Cleaner và Wallpaper vẫn giữ mã nguồn lõi để Patch có thể dùng khi cần, nhưng không còn icon ở thanh tab.
- Trang chủ được làm lại theo bố cục dashboard: logo + tên Tizi Mod, thông tin iOS/thiết bị/tương thích, lưới ứng dụng hỗ trợ, trạng thái key và nút đổi key.
- Màu giao diện dashboard: nền navy đậm kết hợp xanh nước biển nhạt/cyan theo nhận diện Tizi Mod.
- Next DNS có ô lưu Profile ID, tạo địa chỉ DoH và nút sao chép/mở dashboard NextDNS.

## Key Server đầy đủ

Bản này bổ sung thư mục `key-server/` và kết nối app với server key.

- Key hiển thị mã đã che, thời gian còn lại và ngày giờ hết hạn trên Trang Chủ.
- App lưu session token trong Keychain và kiểm tra trạng thái server định kỳ.
- Admin server có tạo key theo giờ/ngày/tuần/tháng, giới hạn thiết bị, cộng/trừ thời gian, đặt ngày hết hạn, khóa/mở khóa, reset máy, xóa key, xuất CSV và nhật ký.
- Sửa `TiziKeyServerURL` trong `ThreeOneOSFive/Info.plist` thành domain HTTPS của server trước khi build bản Release.

Xem `KEY_SERVER_GUIDE.vi.md` để cài server.
