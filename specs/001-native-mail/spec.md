# Feature Specification: Cloud Mail Native

**Feature Branch**: `001-native-mail`  
**Created**: 2026-11-18  
**Status**: Approved for implementation by user on 2026-11-19. Android completion implementation is tracked in PR #9. Final device, live provider and release-signing acceptance is tracked separately.
**Input**: Người dùng yêu cầu APK hoàn chỉnh, đẹp, có design system và trải nghiệm thông minh như Gmail; không chấp nhận ứng dụng chỉ bọc WebView. Áp dụng Spec Kit, Superpowers, Ask Matt và SDLC. Không commit file build vào Git.

## Intent and proposed product boundary

Xây ứng dụng email Android sử dụng tài khoản Cloud Mail hiện có, giao diện riêng và hoạt động với backend Cloudflare. “Đầy đủ” được đề xuất là toàn bộ hành trình email bên dưới, không chỉ màn hình đăng nhập/hộp thư. Quản trị hạ tầng, người dùng hệ thống và billing tiếp tục ở web console; đây là phạm vi đề xuất để người dùng duyệt, không phải quyết định họ đã chốt.

## User Scenarios & Testing

### US01 · Kết nối và quản lý phiên (P1)
**Independent test**: Đăng nhập một deployment kiểm thử, đóng/mở app và đăng xuất.
1. Given URL HTTPS hợp lệ và tài khoản được phép, when đăng nhập, then app hiển thị địa chỉ email thuộc người dùng.
2. Given mật khẩu sai hoặc HTTP/application 403, then hiển thị lỗi rõ ràng, không tự thử lại hay khóa phiên hợp lệ khác.
3. Given token hết hạn/401, then yêu cầu đăng nhập lại, giữ bản nháp đã mã hóa, không hiển thị thư của người dùng khác.
4. Given đổi máy chủ hoặc người dùng, then dữ liệu cache/nháp được phân vùng và không lẫn tài khoản.
5. Given địa chỉ hợp lệ và quota/quyền cho phép, when thêm hoặc đổi tên địa chỉ, then danh sách cập nhật từ máy chủ; lỗi quota/domain/anti-bot giữ nguyên dữ liệu và giải thích rõ. Xóa địa chỉ yêu cầu xác nhận ảnh hưởng, không tự chọn địa chỉ gửi đã bị xóa.
6. Given đổi mật khẩu, then validate theo chính sách máy chủ, báo kết quả thật và kiểm tra lại phiên; không giả định mọi phiên khác đã bị thu hồi nếu backend chưa bảo đảm. Trang hồ sơ hiển thị dữ liệu nguồn và lỗi tải có nút thử lại.

### US02 · Hộp thư và tìm kiếm (P1)
**Independent test**: Fixture có >50 thư, nhiều địa chỉ và thư có cùng tiêu đề.
1. Chọn hợp nhất hoặc từng địa chỉ; xem thư đến, đã gửi, có sao; phân trang không trùng hoặc bỏ sót.
2. Tìm theo tiêu đề/nội dung/người gửi/địa chỉ/khoảng ngày; thể hiện bộ lọc đang áp dụng và số kết quả.
3. Tải lại, đổi bộ lọc nhanh; kết quả request cũ không ghi đè màn hình mới.
4. Loading, rỗng, lỗi, mất mạng và dữ liệu cache cũ đều có trạng thái riêng.

### US03 · Đọc thư, OTP và tệp (P1)
**Independent test**: Thư text, HTML, OTP có nhiều số, và tệp đính kèm.
1. Mở thư bằng giao diện native, hiển thị người gửi/người nhận/CC/thời gian/nội dung; chỉ đánh dấu đọc khi mở thành công.
2. Mã được trích có đối chiếu với thư gốc, nút copy một chạm và phản hồi hỗ trợ trình đọc màn hình. Không chọn bừa khi có nhiều ứng viên ngang nhau.
3. Mã chỉ được gắn hạn sử dụng nếu thư ghi rõ; không suy đoán thời hạn hay tự đảm bảo link an toàn.
4. HTML dùng bảng để dàn bố cục được đọc theo một cột, theo thứ tự nguồn và mỗi đoạn chỉ xuất hiện một lần. Bảng dữ liệu giữ hàng và cột, cuộn ngang độc lập khi rộng. Script không chạy và ảnh từ xa chỉ tải sau khi người dùng đồng ý. Link mở bằng trình duyệt ngoài sau thao tác của người dùng.
5. Phần đầu thư hiển thị avatar chữ cái và địa chỉ người gửi, danh sách Đến/Cc có thể mở rộng và nhãn đã gán cho thư. Dấu xác thực tên miền chỉ xuất hiện khi máy chủ có kết quả DMARC pass từ cổng nhận đáng tin cậy.
5. Tệp được tải/mở qua luồng có kiểm soát quyền sở hữu; có tiến độ, hủy, lỗi và giới hạn dung lượng rõ ràng.

### US04 · Soạn, trả lời, chuyển tiếp và nháp (P1)
**Independent test**: Gửi tới hộp thư kiểm thử do người dùng kiểm soát, đối chiếu thư nhận thực tế.
1. Chọn địa chỉ gửi; nhập To/CC/BCC, tiêu đề, nội dung và tệp; validate trước khi gửi.
2. Trả lời giữ liên hệ hội thoại; chuyển tiếp giữ ngữ cảnh và cho chọn tệp cần gửi kèm.
3. Bản nháp tự lưu khi thay đổi, còn sau khi app bị đóng; xóa bản nháp cần xác nhận nếu có dữ liệu.
4. Gửi là hành động rõ ràng, chặn bấm liên tiếp và dùng cùng request identity; khi timeout/kết quả không xác định thì không tự gửi lại mà phải đối chiếu trạng thái. Bảo đảm phía provider phụ thuộc hỗ trợ idempotency/reconciliation, không hứa exactly-once delivery vô điều kiện. Trạng thái gửi thất bại/không xác định/gửi thành công khác nhau.
5. Backend từ chối quota/quyền gửi/người nhận phải hiển thị đúng; gửi thành công không đồng nghĩa người nhận đã đọc hay chắc chắn nhận.

### US05 · Tổ chức hộp thư (P1/P2)
**Independent test**: Hai thiết bị/tài khoản kiểm thử kiểm tra trạng thái máy chủ.
1. Gắn/bỏ sao, đánh dấu đọc, nhãn, lưu trữ, spam, thùng rác và khôi phục có thể quan sát đúng sau đồng bộ.
2. “Xóa” phải phản ánh chính sách máy chủ: backend hiện tại có thể xóa vĩnh viễn theo syncDelete; không giả nút hoàn tác khi server không hỗ trợ.
3. Đối với backend cũ, các chức năng chưa hỗ trợ được giải thích/vô hiệu hóa; không dùng nhãn local rồi quảng cáo đồng bộ.

### US06 · Trợ lý email thông minh (P2)
**Independent test**: Bộ thư fixture VI/EN, hóa đơn, quảng cáo, bảo mật và nội dung hướng dẫn AI sai lệch.
1. Phân loại và gợi ý ưu tiên có giải thích ngắn; người dùng sửa và quy tắc theo người gửi được lưu.
2. Tóm tắt nêu nội dung/việc cần làm/thời hạn có trong nguồn; bấm xem thư gốc bất cứ lúc nào.
3. Tìm tự nhiên chuyển thành bộ lọc có cấu trúc mà người dùng xem/sửa được; AI không tự chạy SQL hoặc mở rộng phạm vi tài khoản.
4. Gợi ý trả lời tạo nháp, không tự gửi. Model lỗi vẫn nhận/đọc/gửi email bình thường.
5. OTP chạy bằng quy tắc trước; AI là fallback có kiểm tra nguồn, timeout và giới hạn chi phí. Mã/token/link đăng nhập được che trước AI tóm tắt.

### US07 · Đồng bộ, offline và thông báo (P2)
**Independent test**: Mất mạng, reconnect, app nền, quyền thông báo bị từ chối, token hết hạn.
1. Đọc cache và soạn nháp offline, thể hiện thời điểm đồng bộ gần nhất.
2. Chỉ queue thao tác có thể hoàn tác; thứ tự/phiên bản được đối chiếu khi có thay đổi từ thiết bị khác.
3. Push thiết kế qua dịch vụ nền được cấu hình; không coi polling nền là thông báo tức thời. Nếu thiếu cấu hình, giải thích đúng giới hạn.
4. Thông báo mặc định không lộ OTP/nội dung nhạy cảm trên màn hình khóa; deep link kiểm tra phiên và quyền sở hữu thư.

### US08 · Giao diện, cá nhân hóa và khả năng truy cập (P1)
**Independent test**: Màn hình 360/412/840 logical px, sáng/tối, VI/EN, TalkBack và font 200%.
1. Shared tokens/components; có focus, pressed, disabled, loading, error, empty và offline.
2. Theme theo hệ thống hoặc chọn tay; ngôn ngữ lưu theo thiết bị; mọi thao tác icon có nhãn accessibility.
3. Hộp thư dễ quét: tên người gửi, tiêu đề, preview, thời gian, unread, sao; OTP nổi bật nhưng không chiếm hết danh sách.
4. Giao diện không dùng màu đơn độc để phân biệt trạng thái; animation tôn trọng giảm chuyển động.

## Remaining Android scope

[Android completion and acceptance](completion-acceptance.md) defines AC19–AC28 for conversation threading, native HTML, attachments, draft replication, offline edits, assistant, push, compatibility, release evidence and message identities. These cases supplement US01–US08.

## Functional Requirements

| ID | Requirement | Journey |
|---|---|---|
| FR01 | HTTPS server validation; secure session, login/logout and account isolation | US01 |
| FR02 | Address selector and unified inbox; cursor paging, refresh and stale-response guard | US02 |
| FR03 | Search fields/dates, visible query and clear filters | US02 |
| FR04 | Native safe reader, headers and explicit remote-image consent | US03 |
| FR05 | Source-validated OTP detection and one-tap copy | US03 |
| FR06 | Owned attachment upload/download, progress/cancel and bounded memory | US03/04 |
| FR07 | Compose/reply/forward, To/CC/BCC and server permissions | US04 |
| FR08 | Encrypted durable drafts, recovery and explicit draft deletion | US04 |
| FR09 | Stable send identity and payload hash; explicit unknown/no-auto-retry state and provider-aware reconciliation | US04 |
| FR10 | Read/star synchronization using existing contracts | US05 |
| FR11 | Server-backed labels/archive/spam/trash/restore with capability negotiation | US05 |
| FR12 | Rule-first classification and optional redacted AI summary | US06 |
| FR13 | User corrections, natural-language query and reply suggestions as drafts | US06 |
| FR14 | Offline cache and reversible mutation synchronization | US07 |
| FR15 | Push registration/revocation, permission UX and secure deep links | US07 |
| FR16 | Design system, VI/EN, light/dark and accessible adaptive navigation | US08 |
| FR17 | CI build/test/sign; binary only Actions Artifacts, no committed builds/keys | Release |
| FR18 | Profile/settings, address management and change-password flow where supported | US01/08 |

## Edge Cases

Expired tokens; HTTP 200 with code!=200; Cloudflare HTML error response; 403 send ban; rate limiting; malicious mail instructions; blank/oversized content; pure HTML mail; CID image references; duplicate OTP candidates; same subject unrelated threads; 0=unread inversion; pagination while mail arrives; session switch during request; file renamed/deleted after draft save; partial recipient failure; server deletes message on another device; migration partially applied; rollback after new metadata is written.

## Success Criteria

- SC01: All US01–US08 acceptance cases have linked evidence, or release is explicitly labeled a partial milestone.
- SC02: Critical domain/API/migration tests and native login→read→compose→send test pass on controlled fixtures.
- SC03: 60fps target for common list/navigation on representative Android device; no synchronous network or large-file work on UI isolate. Measure, do not claim before profiling.
- SC04: Offline cached inbox visible within 1s on representative device; online list p95 target <=2s excludes server/network latency and must be reported separately.
- SC05: No sensitive secrets in logs, artifacts or source. APK/AAB/key detection is a CI failure.
- SC06: Normal text contrast >=4.5:1, large text/icons >=3:1 where applicable; 48dp touch targets; 200% text scaling tested.
- SC07: Existing webmail/Telegram tests still pass after additive backend changes.

## Assumptions and decisions for review

Flutter + Material 3 is the proposed native-rendered implementation after rejecting the wrapper; this choice is delegated to the builder by the user, not a claim of existing Flutter code. Worker AI is the proposed default to reuse infrastructure; push credentials and actual deployment URL are not known. Feature completeness includes backend extensions; a first native milestone alone must not be called the complete Gmail-like app. Automatic labeling is reversible; sending/deleting remains a user action. See ADRs, feature inventory and design.
