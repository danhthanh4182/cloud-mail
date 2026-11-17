# User-flow sketch

```mermaid
flowchart TD
    Start["Mở ứng dụng"] --> Session{"Phiên còn hiệu lực?"}
    Session -->|Không| Login["Máy chủ và đăng nhập"]
    Session -->|Có| Inbox["Hộp thư"]
    Login --> Inbox
    Inbox --> Search["Tìm và lọc"]
    Inbox --> Reader["Đọc thư và OTP"]
    Search --> Reader
    Inbox --> Drafts["Bản nháp"]
    Reader --> Compose["Trả lời hoặc chuyển tiếp"]
    Drafts --> Compose
    Compose --> Confirm{"Xác nhận gửi"}
    Confirm -->|Gửi| Send["Gửi và đối chiếu kết quả"]
    Confirm -->|Để sau| Saved["Lưu nháp mã hóa"]
    Reader --> Organize["Sao, nhãn và thư mục"]
```

## State sketches
- Inbox: toolbar → heading/unread count → search → folder filters → priority OTP → mail rows → floating compose → bottom navigation.
- Reader: back/actions → subject/labels → sender/time → optional generated summary → original native-rendered body → attachments → reply/forward.
- Compose: close/title/send → sender → To/CC/BCC → subject → body → attachments → formatting/insert bar → draft status.
- Login: brand/title → deployment URL → email/password → field errors → sign in → server capability/permission errors.

Wireframe mode in mockup.html removes color/elevation and exposes the same layout structure. Detailed secondary screens remain in task T002 and are not claimed as finished high-fidelity screens.
