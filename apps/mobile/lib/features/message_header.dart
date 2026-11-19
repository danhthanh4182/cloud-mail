import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../design_system/components.dart';
import '../domain/mail.dart';

class MessageHeader extends StatelessWidget {
  final AppController state;
  final MailMessage mail;
  const MessageHeader({super.key, required this.state, required this.mail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sender = mail.displayName.isEmpty
        ? state.t('Không rõ người gửi', 'Unknown sender')
        : mail.displayName;
    final to = mail.toPeople;
    final cc = mail.ccPeople;
    final recipients = [...to, ...cc];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(mail.displayName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sender, style: theme.textTheme.titleMedium),
                  if (mail.sender.isNotEmpty && mail.sender != sender)
                    Text(mail.sender, style: theme.textTheme.bodyMedium),
                  if (mail.time.isNotEmpty)
                    Text(
                      mail.time,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (mail.authenticatedDomain case final String domain)
                    SenderAuthenticationBadge(state: state, domain: domain),
                ],
              ),
            ),
          ],
        ),
        if (recipients.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            leading: Avatar(recipients.first.displayName, size: 32),
            title: Text(
              '${to.isEmpty ? 'Cc' : state.t('Đến', 'To')} · '
              '${recipients.first.displayName}'
              '${recipients.length == 1 ? '' : ' +${recipients.length - 1}'}',
              style: theme.textTheme.bodyMedium,
            ),
            children: [
              if (to.isNotEmpty)
                _RecipientGroup(title: state.t('Đến', 'To'), people: to),
              if (cc.isNotEmpty) _RecipientGroup(title: 'Cc', people: cc),
            ],
          ),
        ],
      ],
    );
  }
}

class _RecipientGroup extends StatelessWidget {
  final String title;
  final List<MailParticipant> people;
  const _RecipientGroup({required this.title, required this.people});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.labelLarge),
          for (final person in people)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Avatar(person.displayName, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(person.displayName, style: text.bodyMedium),
                        if (person.name.isNotEmpty &&
                            person.name != person.address)
                          Text(person.address, style: text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class SenderAuthenticationBadge extends StatelessWidget {
  final AppController state;
  final String domain;
  final bool compact;
  const SenderAuthenticationBadge({
    super.key,
    required this.state,
    required this.domain,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final title = state.t('Tên miền đã xác thực', 'Authenticated domain');
    final icon = Icon(
      Icons.verified_user_outlined,
      size: compact ? 18 : 16,
      color: Theme.of(context).colorScheme.primary,
    );
    if (compact) {
      return Tooltip(message: '$title · $domain', child: icon);
    }
    return ActionChip(
      avatar: icon,
      label: Text(title),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(
            state.t(
              'Cloudflare Email Routing xác thực tên miền $domain bằng DMARC. Kết quả này áp dụng cho tên miền gửi thư. Hãy kiểm tra địa chỉ đầy đủ trước khi tin tưởng người gửi.',
              'Cloudflare Email Routing confirmed $domain with DMARC. This result applies to the sending domain. Check the full address before trusting the sender.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(state.t('Đóng', 'Close')),
            ),
          ],
        ),
      ),
    );
  }
}
