/// Turns a natural-language query into the existing editable search fields.
/// Dates are UTC because the mail list uses D1's UTC date boundaries.
Map<String, String> interpretMailSearch(String input, {DateTime? now}) {
  final source = input.trim();
  final period = RegExp(
    r'\b(today|yesterday|last (?:7 days|week))\b|hôm nay|hôm qua|(?:7 ngày qua|tuần qua)',
    caseSensitive: false,
  );
  final address = RegExp(
    r'(?:^|\s)(from:|to:|from\s+|to\s+|từ\s+|đến\s+)([^\s<>]+@[^\s<>]+)',
    caseSensitive: false,
  ).firstMatch(source);
  final when = period.firstMatch(source)?.group(0)?.toLowerCase();
  final date = (now ?? DateTime.now()).toUtc();
  String day(int offset) =>
      date.subtract(Duration(days: offset)).toIso8601String().split('T').first;
  final yesterday = when == 'yesterday' || when == 'hôm qua';
  final today = when == 'today' || when == 'hôm nay';
  final phrase = source
      .replaceFirst(period, '')
      .trim()
      .replaceFirst(
        RegExp(
          r'^(?:find|search(?: for)?|tìm(?: kiếm)?)(?=\s|$)\s*',
          caseSensitive: false,
        ),
        '',
      );
  final body = RegExp(
    r'^(?:body:\s*|contains\s+|nội dung\s+)(.*)$',
    caseSensitive: false,
  ).firstMatch(phrase);
  final to = address?.group(1)?.toLowerCase().trim();
  return {
    'field': address != null
        ? ((to!.startsWith('to') || to == 'đến')
              ? 'recipientAddress'
              : 'senderAddress')
        : body == null
        ? 'subject'
        : 'content',
    'text': address != null
        ? address.group(2)!.replaceFirst(RegExp(r'[,.!?]+$'), '')
        : (body?.group(1) ?? phrase).trim().replaceAll(
            RegExp(r'^["“]|["”]$'),
            '',
          ),
    'startDate': when == null
        ? ''
        : day(
            yesterday
                ? 1
                : today
                ? 0
                : 6,
          ),
    'endDate': when == null ? '' : day(yesterday ? 1 : 0),
  };
}
