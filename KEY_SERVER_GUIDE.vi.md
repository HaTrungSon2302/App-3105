# Tizi Mod Key Server

Server quản lý key đi kèm app Tizi Mod. Dữ liệu lưu trong SQLite, không cần MySQL.

## Chức năng

- Tạo 1 hoặc nhiều key ngẫu nhiên.
- Thời hạn theo **giờ / ngày / tuần / tháng (30 ngày)**.
- Chọn **tính thời gian từ lúc tạo** hoặc **bắt đầu từ lần kích hoạt đầu tiên**.
- Giới hạn số thiết bị trên mỗi key.
- Xem key chưa dùng / đang chạy / hết hạn / đã khóa.
- Cộng hoặc trừ giờ/ngày/tuần/tháng.
- Đặt ngày giờ hết hạn chính xác.
- Khóa / mở khóa key.
- Reset thiết bị và phiên đăng nhập.
- Xóa từng key hoặc xóa toàn bộ key hết hạn.
- Tìm kiếm, ghi chú, xuất CSV và xem nhật ký sự kiện.
- App kiểm tra lại trạng thái server định kỳ, nên key bị xóa/khóa/hết hạn sẽ không tiếp tục dùng lâu dài.

## Chạy thử trên Windows

1. Cài Python 3.11+.
2. Mở thư mục `key-server`.
3. Nhấp đúp `start_windows.bat` hoặc chạy:

```bat
py -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
python app.py
```

4. Mở `http://127.0.0.1:8000/admin`.
5. Mật khẩu nằm trong `.env` ở biến `ADMIN_PASSWORD`.

**Hãy đổi ngay `ADMIN_PASSWORD` và `SECRET_KEY`.**

## Cấu hình app iOS

Trong file:

`ThreeOneOSFive/Info.plist`

đổi:

```xml
<key>TiziKeyServerURL</key>
<string>https://key.tenmiencuaban.com</string>
```

App dùng:

- `POST /api/v1/activate`
- `GET /api/v1/status`
- `POST /api/v1/logout`

Trên iPhone nên dùng **HTTPS**. Không nên để HTTP công khai.

## Đưa lên VPS Ubuntu

Ví dụ server đặt ở `/opt/tizi-key-server`:

```bash
sudo apt update
sudo apt install -y python3-venv nginx certbot python3-certbot-nginx
sudo mkdir -p /opt/tizi-key-server
sudo chown -R $USER:$USER /opt/tizi-key-server
cd /opt/tizi-key-server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
nano .env
```

Chạy thử:

```bash
.venv/bin/gunicorn -w 2 -b 127.0.0.1:8000 app:app
```

Tạo service `/etc/systemd/system/tizi-key.service`:

```ini
[Unit]
Description=Tizi Mod Key Server
After=network.target

[Service]
User=YOUR_LINUX_USER
WorkingDirectory=/opt/tizi-key-server
EnvironmentFile=/opt/tizi-key-server/.env
ExecStart=/opt/tizi-key-server/.venv/bin/gunicorn -w 2 -b 127.0.0.1:8000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
```

Sau đó:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now tizi-key
```

Nginx `/etc/nginx/sites-available/tizi-key`:

```nginx
server {
    listen 80;
    server_name key.tenmiencuaban.com;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Bật site và HTTPS:

```bash
sudo ln -s /etc/nginx/sites-available/tizi-key /etc/nginx/sites-enabled/tizi-key
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d key.tenmiencuaban.com
```

Sau khi HTTPS hoạt động, sửa `.env`:

```env
COOKIE_SECURE=1
```

rồi:

```bash
sudo systemctl restart tizi-key
```

## API mẫu

Kích hoạt:

```json
POST /api/v1/activate
{
  "key": "TIZI-ABCD-EFGH-IJKL",
  "deviceID": "...",
  "deviceModel": "iPhone16,2",
  "appVersion": "1.0.1"
}
```

Trả về:

```json
{
  "success": true,
  "token": "...",
  "key_masked": "TIZI-ABCD-••••-IJKL",
  "expires_at": "2026-10-19T07:00:00Z",
  "remaining_seconds": 2592000,
  "status": "active"
}
```

## Lưu ý bảo mật

- Không commit file `.env` hoặc database lên GitHub public.
- Dùng mật khẩu admin dài, khác các mật khẩu khác.
- Backup thư mục `data/` định kỳ.
- Key/license kiểm tra ở client vẫn có thể bị người có kỹ năng reverse-engineer bỏ qua; server-side validation, token ngẫu nhiên và kiểm tra trạng thái định kỳ chỉ làm việc bypass khó hơn, không thể bảo đảm tuyệt đối.
