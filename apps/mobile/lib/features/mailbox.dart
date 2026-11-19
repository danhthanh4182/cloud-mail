import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../domain/mail.dart';
import '../domain/smart_mail.dart';
import '../design_system/components.dart';
import 'compose.dart';
import 'reader.dart';
import 'settings.dart';

class MailboxScreen extends StatefulWidget {
  final AppController state;
  const MailboxScreen({super.key, required this.state});
  @override
  State<MailboxScreen> createState() => _MailboxScreenState();
}

class _MailboxScreenState extends State<MailboxScreen>
    with WidgetsBindingObserver {
  final search = TextEditingController();
  Timer? debounce, poll;
  AppController get s => widget.state;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPoll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (s.capabilities.push) {
        pushChannel.setMethodCallHandler((call) async {
          if (call.method == 'mail') await openNotification();
        });
        unawaited(checkNotifications());
      }
    });
  }

  Future<void> checkNotifications() async {
    await s.refreshPush();
    if (mounted) await openNotification();
  }

  Future<void> openNotification() async {
    if (!mounted || !s.signedIn) return;
    final mail = await action(context, s.takeNotification);
    if (mounted && mail != null) {
      final opened = await action(context, () => s.open(mail));
      if (mounted && opened != null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReaderScreen(state: s, mail: opened),
          ),
        );
      }
    }
  }

  Future<void> refresh() =>
      s.folder == 'drafts' ? s.syncDrafts() : s.loadMessages();

  void _startPoll() {
    poll?.cancel();
    poll = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          !s.loading &&
          s.query.isEmpty) {
        unawaited(refresh());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPoll();
      if (ModalRoute.of(context)?.isCurrent == true) unawaited(refresh());
      if (s.capabilities.push) unawaited(checkNotifications());
    } else {
      poll?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    poll?.cancel();
    debounce?.cancel();
    pushChannel.setMethodCallHandler(null);
    search.dispose();
    super.dispose();
  }

  String title(String f) => switch (f) {
    'inbox' => s.t('Hộp thư đến', 'Inbox'),
    'star' => s.t('Có gắn sao', 'Starred'),
    'drafts' => s.t('Bản nháp', 'Drafts'),
    'settings' => s.t('Cài đặt', 'Settings'),
    'sent' => s.t('Đã gửi', 'Sent'),
    'archive' => s.t('Lưu trữ', 'Archive'),
    'spam' => 'Spam',
    'trash' => s.t('Thùng rác', 'Trash'),
    _ => f,
  };
  void choose(String f) {
    search.clear();
    debounce?.cancel();
    s.selectFolder(f);
  }

  void compose([MailDraft? draft]) {
    if (s.addresses.isEmpty) {
      showNotice(
        context,
        s.t(
          'Thêm địa chỉ email trong Cài đặt trước.',
          'Add an email address in Settings first.',
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ComposeScreen(state: s, draft: draft),
      ),
    );
  }

  Future<void> smartSearch() async {
    var query = '';
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('Tìm bằng câu tự nhiên', 'Natural-language search')),
        content: TextField(
          autofocus: true,
          maxLength: 200,
          onChanged: (value) => query = value,
          decoration: InputDecoration(
            hintText: s.t(
              'Thư từ ten@example.com hôm qua',
              'Mail from name@example.com yesterday',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.t('Hủy', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, query),
            child: Text(s.t('Xem bộ lọc', 'Preview filters')),
          ),
        ],
      ),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;
    final filters = interpretMailSearch(text);
    var field = filters['field']!;
    var term = filters['text']!;
    var from = filters['startDate']!;
    var to = filters['endDate']!;
    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('Xác nhận bộ lọc', 'Review search filters')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: field,
                items: [
                  for (final entry in searchFields.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) => field = value ?? field,
              ),
              TextFormField(
                initialValue: term,
                onChanged: (value) => term = value,
                decoration: InputDecoration(
                  labelText: s.t('Từ khóa hoặc địa chỉ', 'Keyword or address'),
                ),
              ),
              TextFormField(
                initialValue: from,
                onChanged: (value) => from = value,
                decoration: InputDecoration(
                  labelText: s.t(
                    'Từ ngày UTC (YYYY-MM-DD)',
                    'From UTC date (YYYY-MM-DD)',
                  ),
                ),
              ),
              TextFormField(
                initialValue: to,
                onChanged: (value) => to = value,
                decoration: InputDecoration(
                  labelText: s.t(
                    'Đến ngày UTC (YYYY-MM-DD)',
                    'To UTC date (YYYY-MM-DD)',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.t('Hủy', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.t('Tìm thư', 'Search')),
          ),
        ],
      ),
    );
    if (!mounted || apply != true) return;
    final valid = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if ([from, to].any(
      (d) =>
          d.isNotEmpty && (!valid.hasMatch(d) || DateTime.tryParse(d) == null),
    )) {
      showNotice(context, s.t('Ngày không hợp lệ.', 'Invalid date.'));
      return;
    }
    debounce?.cancel();
    search.text = term;
    s.query = term;
    s.searchType = field;
    s.startDate = from;
    s.endDate = to;
    await s.loadMessages();
  }

  Map<String, String> get searchFields => {
    'subject': s.t('Tiêu đề', 'Subject'),
    'content': s.t('Nội dung', 'Body'),
    'senderAddress': s.t('Người gửi', 'Sender'),
    'recipientAddress': s.t('Người nhận', 'Recipient'),
  };

  Future<void> filters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.t('Bộ lọc tìm kiếm', 'Search filters'),
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in {
                    'subject': s.t('Tiêu đề', 'Subject'),
                    'content': s.t('Nội dung', 'Body'),
                    'senderAddress': s.t('Người gửi', 'Sender'),
                    'recipientAddress': s.t('Người nhận', 'Recipient'),
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: s.searchType == entry.key,
                      onSelected: (_) {
                        s.searchType = entry.key;
                        Navigator.pop(ctx);
                        s.loadMessages();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text(
                  s.startDate.isEmpty
                      ? s.t('Chọn khoảng ngày', 'Choose date range')
                      : '${s.startDate} → ${s.endDate}',
                ),
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: ctx,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (range != null) {
                    s.startDate = range.start
                        .toIso8601String()
                        .split('T')
                        .first;
                    s.endDate = range.end.toIso8601String().split('T').first;
                    if (ctx.mounted) Navigator.pop(ctx);
                    s.loadMessages();
                  }
                },
              ),
              TextButton(
                onPressed: () {
                  s.startDate = '';
                  s.endDate = '';
                  s.searchType = 'subject';
                  Navigator.pop(ctx);
                  s.loadMessages();
                },
                child: Text(s.t('Xóa bộ lọc', 'Clear filters')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: s,
    builder: (context, _) {
      final wide = MediaQuery.sizeOf(context).width >= 840;
      final selected = switch (s.folder) {
        'star' => 1,
        'drafts' => 2,
        'settings' => 3,
        _ => 0,
      };
      final items = [
        NavigationDestination(
          icon: const Icon(Icons.inbox_outlined),
          selectedIcon: const Icon(Icons.inbox),
          label: s.t('Hộp thư', 'Inbox'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.star_border),
          selectedIcon: const Icon(Icons.star),
          label: s.t('Có sao', 'Starred'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.edit_note),
          label: s.t('Nháp', 'Drafts'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          label: s.t('Cài đặt', 'Settings'),
        ),
      ];
      return Scaffold(
        appBar: AppBar(
          title: Text(title(s.folder)),
          actions: [
            if (s.capabilities.smartMail &&
                !['settings', 'drafts'].contains(s.folder))
              IconButton(
                tooltip: s.t(
                  'Tìm bằng câu tự nhiên',
                  'Natural-language search',
                ),
                icon: const Icon(Icons.auto_awesome_outlined),
                onPressed: smartSearch,
              ),
            if (s.folder != 'settings')
              IconButton(
                tooltip: s.t('Làm mới', 'Refresh'),
                onPressed: s.loading || s.draftsSyncing ? null : refresh,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Cloud Mail',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text('${s.profile['email'] ?? ''}'),
                const SizedBox(height: 24),
                ListTile(
                  leading: const Icon(Icons.all_inbox_outlined),
                  title: Text(s.t('Tất cả địa chỉ', 'All addresses')),
                  selected: s.selectedAddress == null,
                  onTap: () {
                    Navigator.pop(context);
                    s.selectAddress(null);
                  },
                ),
                for (final a in s.legacyStarred ? <MailAddress>[] : s.addresses)
                  ListTile(
                    leading: Avatar(
                      a.name.isEmpty ? a.email : a.name,
                      size: 32,
                    ),
                    title: Text(a.name.isEmpty ? a.email : a.name),
                    subtitle: a.name.isEmpty ? null : Text(a.email),
                    selected: s.selectedAddress == a.id,
                    onTap: () {
                      Navigator.pop(context);
                      s.selectAddress(a.id);
                    },
                  ),
                const Divider(),
                for (final f in [
                  'inbox',
                  'sent',
                  'star',
                  if (s.capabilities.organization) ...[
                    'archive',
                    'spam',
                    'trash',
                  ],
                  'drafts',
                  'settings',
                ])
                  ListTile(
                    title: Text(title(f)),
                    selected: s.folder == f,
                    onTap: () {
                      Navigator.pop(context);
                      choose(f);
                    },
                  ),
              ],
            ),
          ),
        ),
        body: Row(
          children: [
            if (wide)
              NavigationRail(
                selectedIndex: selected,
                onDestinationSelected: (i) =>
                    choose(['inbox', 'star', 'drafts', 'settings'][i]),
                labelType: NavigationRailLabelType.all,
                destinations: items
                    .map(
                      (e) => NavigationRailDestination(
                        icon: e.icon,
                        selectedIcon: e.selectedIcon,
                        label: Text(e.label),
                      ),
                    )
                    .toList(),
              ),
            Expanded(
              child: s.folder == 'settings'
                  ? SettingsScreen(state: s)
                  : Column(
                      children: [
                        if (s.offline) ConnectionBanner(s),
                        if (s.loading)
                          const LinearProgressIndicator(minHeight: 2),
                        if (s.legacyStarred)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              s.t(
                                'Máy chủ cũ hiển thị thư có sao của tất cả địa chỉ và chưa lọc được.',
                                'The older server lists starred mail across all addresses without filters.',
                              ),
                            ),
                          ),
                        if (s.folder != 'drafts' && !s.legacyStarred)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                            child: TextField(
                              controller: search,
                              onChanged: (value) {
                                debounce?.cancel();
                                debounce = Timer(
                                  const Duration(milliseconds: 400),
                                  () {
                                    s.query = value;
                                    s.loadMessages();
                                  },
                                );
                              },
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: s.t(
                                  'Tìm trong thư của bạn',
                                  'Search your mail',
                                ),
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: IconButton(
                                  tooltip: s.t('Bộ lọc', 'Filters'),
                                  onPressed: filters,
                                  icon: const Icon(Icons.tune),
                                ),
                              ),
                            ),
                          ),
                        if (!s.legacyStarred &&
                            (s.startDate.isNotEmpty || s.endDate.isNotEmpty))
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: InputChip(
                                label: Text('${s.startDate} → ${s.endDate}'),
                                onDeleted: () {
                                  s.startDate = '';
                                  s.endDate = '';
                                  s.loadMessages();
                                },
                              ),
                            ),
                          ),
                        if (!s.legacyStarred &&
                            s.folder != 'drafts' &&
                            s.query.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                s.t(
                                  '${searchFields[s.searchType]} · ${s.messages.length} thư đã tải',
                                  '${searchFields[s.searchType]} · ${s.messages.length} loaded',
                                ),
                              ),
                            ),
                          ),
                        if (s.folder == 'drafts' && s.capabilities.draftSync)
                          ListTile(
                            leading: const Icon(Icons.sync),
                            title: Text(
                              s.draftsSyncing
                                  ? s.t('Đang đồng bộ nháp', 'Syncing drafts')
                                  : s.t('Đồng bộ bản nháp', 'Sync drafts'),
                            ),
                            subtitle: Text(
                              s.draftSyncStatus.isNotEmpty
                                  ? s.draftSyncStatus
                                  : s.t(
                                      'Đồng bộ văn bản, tệp gốc giữ trên máy.',
                                      'Text syncs. Original attachments stay on the device.',
                                    ),
                            ),
                            onTap: s.draftsSyncing ? null : s.syncDrafts,
                          ),
                        if (s.pendingEdits.isNotEmpty)
                          ListTile(
                            leading: const Icon(Icons.cloud_off_outlined),
                            title: Text(
                              s.t(
                                '${s.pendingEdits.length} thay đổi đang giữ trên máy',
                                '${s.pendingEdits.length} pending changes',
                              ),
                            ),
                            subtitle: Text(
                              s.pendingEdits.any((edit) => edit.conflict)
                                  ? s.t(
                                      'Có xung đột. Bỏ các thay đổi chờ rồi mở lại thư để chỉnh trên bản mới.',
                                      'Conflict. Discard pending changes and reopen the latest version to edit.',
                                    )
                                  : s.t(
                                      'App sẽ đồng bộ khi kết nối lại.',
                                      'Changes sync when the app reconnects.',
                                    ),
                            ),
                            trailing: IconButton(
                              tooltip: s.t(
                                'Bỏ thay đổi đang chờ',
                                'Discard pending changes',
                              ),
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: s.editsSyncing
                                  ? null
                                  : () async {
                                      if (await confirm(
                                            context,
                                            s,
                                            s.t(
                                              'Bỏ thay đổi đang chờ?',
                                              'Discard pending changes?',
                                            ),
                                            s.t(
                                              'App sẽ hiển thị trạng thái mới nhất từ máy chủ.',
                                              'The server version will be shown.',
                                            ),
                                          ) &&
                                          context.mounted) {
                                        await action(context, s.discardEdits);
                                      }
                                    },
                            ),
                          ),
                        if (s.offline && s.lastServerSync != null)
                          Text(
                            s.t(
                              'Đồng bộ gần nhất ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(s.lastServerSync!))}',
                              'Last synced ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(s.lastServerSync!))}',
                            ),
                          ),
                        if (s.error.isNotEmpty && !s.offline)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              s.error,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        Expanded(
                          child: s.folder == 'drafts' ? _drafts() : _mail(),
                        ),
                      ],
                    ),
            ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: (i) =>
                    choose(['inbox', 'star', 'drafts', 'settings'][i]),
                destinations: items,
              ),
        floatingActionButton: s.folder == 'settings'
            ? null
            : FloatingActionButton.extended(
                onPressed: () => compose(),
                icon: const Icon(Icons.edit_outlined),
                label: Text(s.t('Soạn thư', 'Compose')),
              ),
      );
    },
  );
  Widget _drafts() => s.drafts.isEmpty
      ? EmptyPanel(
          icon: Icons.edit_note,
          title: s.t('Chưa có bản nháp', 'No drafts yet'),
          body: s.t(
            'Nội dung đang soạn được lưu mã hóa trên thiết bị.',
            'Your drafts are encrypted on this device.',
          ),
        )
      : ListView.builder(
          padding: const EdgeInsets.only(bottom: 100),
          itemCount: s.drafts.length,
          itemBuilder: (context, i) {
            final d = s.drafts[i];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              leading: const Icon(Icons.edit_note),
              title: Text(
                d.subject.isEmpty
                    ? s.t('(Không tiêu đề)', '(No subject)')
                    : d.subject,
              ),
              subtitle: Text(
                '${d.to}\n${d.conflictCopy
                    ? s.t('Bản giữ lại do xung đột', 'Saved conflict copy')
                    : d.outcomeUncertain
                    ? s.t('Cần đối chiếu trạng thái gửi', 'Send status needs reconciliation')
                    : d.body}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: true,
              onTap: s.draftsSyncing ? null : () => compose(d),
              trailing: IconButton(
                tooltip: s.t('Xóa nháp', 'Delete draft'),
                icon: const Icon(Icons.delete_outline),
                onPressed: s.draftsSyncing
                    ? null
                    : () async {
                        if (await confirm(
                          context,
                          s,
                          s.t('Xóa bản nháp?', 'Delete draft?'),
                          d.revision > 0
                              ? s.t(
                                  'Nháp đã đồng bộ sẽ bị xóa trên máy chủ và các thiết bị sau lần đồng bộ tiếp theo.',
                                  'This synced draft will be removed from the server and other devices on the next sync.',
                                )
                              : s.t(
                                  'Nội dung chưa gửi sẽ bị xóa khỏi thiết bị.',
                                  'Unsent content will be removed from this device.',
                                ),
                        )) {
                          if (context.mounted) {
                            await action(context, () => s.deleteDraft(d));
                          }
                        }
                      },
              ),
            );
          },
        );
  Widget _mail() {
    if (s.messages.isEmpty && !s.loading && !s.hasMore) {
      return EmptyPanel(
        icon: Icons.inbox_outlined,
        title: s.query.isNotEmpty
            ? s.t('Không có kết quả', 'No results')
            : s.t('Hộp thư trống', 'All clear'),
        body: s.addresses.isEmpty
            ? s.t(
                'Thêm địa chỉ email trong Cài đặt để bắt đầu.',
                'Add an email address in Settings to begin.',
              )
            : s.t(
                'Thư mới sẽ xuất hiện tại đây. Kéo xuống để làm mới.',
                'New mail will appear here. Pull to refresh.',
              ),
        action: OutlinedButton(
          onPressed: () => s.loadMessages(),
          child: Text(s.t('Thử lại', 'Refresh')),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => s.loadMessages(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
        itemCount: s.messages.length + (s.hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == s.messages.length) {
            return TextButton(
              onPressed: s.loading ? null : () => s.loadMessages(more: true),
              child: Text(s.t('Tải thêm thư', 'Load more')),
            );
          }
          final m = s.messages[i];
          return Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                leading: Avatar(m.displayName),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.displayName.isEmpty
                            ? s.t('Không rõ người gửi', 'Unknown sender')
                            : m.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: m.unread
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      m.time.length >= 10 ? m.time.substring(5, 10) : m.time,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.subject.isEmpty
                          ? s.t('(Không tiêu đề)', '(No subject)')
                          : m.subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: m.unread
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (s.capabilities.smartMail &&
                        m.category.isNotEmpty &&
                        m.category != 'primary')
                      Text(
                        mailCategories(s)[m.category] ?? m.category,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    if (m.code.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: OtpCard(
                          state: s,
                          code: m.code,
                          compact: true,
                          sender: m.displayName,
                        ),
                      ),
                  ],
                ),
                trailing: IconButton(
                  tooltip: m.starred
                      ? s.t('Bỏ sao', 'Remove star')
                      : s.t('Gắn sao', 'Star'),
                  onPressed: () => action(context, () => s.toggleStar(m)),
                  icon: Icon(
                    m.starred ? Icons.star : Icons.star_border,
                    color: m.starred
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                onTap: () async {
                  final mail = await action(context, () => s.open(m));
                  if (context.mounted && mail != null) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ReaderScreen(state: s, mail: mail),
                      ),
                    );
                  }
                },
              ),
              const Divider(height: 1, indent: 58),
            ],
          );
        },
      ),
    );
  }
}
