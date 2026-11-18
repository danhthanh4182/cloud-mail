import 'dart:convert';
import 'dart:math';

import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${List.generate(12, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
int asInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
String asText(dynamic value) => value is String ? value : '';
String plainText(String source) {
  final doc = html.parse(source);
  for (final node in doc.querySelectorAll(
    'script,style,head,iframe,object,form',
  )) {
    node.remove();
  }
  for (final node in doc.querySelectorAll(
    'br,p,div,tr,li,h1,h2,h3,blockquote',
  )) {
    node.nodes.add(dom.Text('\n'));
  }
  return (doc.body?.text ?? '').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

String extractOtp(String subject, String body) {
  final text = '$subject\n$body';
  final pattern = RegExp(
    r'(?:verification|security|one[- ]time|otp|mã\s+(?:xác\s+(?:nhận|minh)|bảo\s+mật)|验证码|code)[^\n\d]{0,50}?\b(\d{3} \d{3}|[A-Z]*\d[A-Z0-9]*)\b',
    caseSensitive: false,
  );
  final candidates = pattern
      .allMatches(text.length > 24000 ? text.substring(0, 24000) : text)
      .map((m) => m.group(1)!.replaceAll(' ', ''))
      .where((x) => x.length >= 4 && x.length <= 12)
      .toSet();
  return candidates.length == 1 ? candidates.single : '';
}

List<String> parseRecipients(String input) {
  final list = <String>[], seen = <String>{};
  for (final raw in input.split(RegExp(r'[,;\n]'))) {
    final address = raw.trim();
    if (address.isEmpty) continue;
    if (!RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$').hasMatch(address)) {
      throw FormatException('Invalid email: $address');
    }
    if (seen.add(address.toLowerCase())) list.add(address);
  }
  if (list.length > 50) {
    throw const FormatException('Maximum 50 recipients per field');
  }
  return list;
}

Uri validateServer(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !['', '/', '/api', '/api/'].contains(uri.path)) {
    throw const FormatException(
      'Use an HTTPS server origin, without credentials or query parameters',
    );
  }
  return uri.replace(path: '');
}

class MailAddress {
  final int id, sort;
  final String email, name;
  const MailAddress({
    required this.id,
    required this.email,
    this.name = '',
    this.sort = 0,
  });
  factory MailAddress.fromJson(Map<String, dynamic> j) => MailAddress(
    id: asInt(j['accountId']),
    email: asText(j['email']),
    name: asText(j['name']),
    sort: asInt(j['sort']),
  );
  Map<String, dynamic> toJson() => {
    'accountId': id,
    'email': email,
    'name': name,
    'sort': sort,
  };
}

class MailMessage {
  final int id, accountId, version, type;
  final String subject, sender, name, to, text, content, time, folder, cc;
  final bool unread, starred;
  final List<String> labels;
  final List<Map<String, dynamic>> attachments;
  const MailMessage({
    required this.id,
    this.accountId = 0,
    this.type = 0,
    this.cc = '',
    this.version = 0,
    this.subject = '',
    this.sender = '',
    this.name = '',
    this.to = '',
    this.text = '',
    this.content = '',
    this.time = '',
    this.folder = 'inbox',
    this.unread = true,
    this.starred = false,
    this.labels = const [],
    this.attachments = const [],
  });
  factory MailMessage.fromJson(Map<String, dynamic> j) => MailMessage(
    id: asInt(j['emailId']),
    accountId: asInt(j['accountId']),
    version: asInt(j['version']),
    type: asInt(j['type']),
    cc: decodeList(j['cc'])
        .map((x) => x is Map ? asText(x['address']) : '$x')
        .join(', '),
    subject: asText(j['subject']),
    sender: asText(j['sendEmail']),
    name: asText(j['name']),
    to: decodeList(j['recipient']).isNotEmpty
        ? decodeList(j['recipient'])
              .map((x) => x is Map ? asText(x['address']) : '$x')
              .join(', ')
        : asText(j['toEmail']),
    text: asText(j['text']),
    content: asText(j['content']),
    time: asText(j['createTime']),
    folder: asText(j['folder']).isEmpty ? 'inbox' : asText(j['folder']),
    unread: asInt(j['unread']) == 0,
    starred: asInt(j['isStar']) == 1 || j['starId'] != null,
    labels: decodeList(j['labels']).map((x) => '$x').toList(),
    attachments: decodeList(j['attList'])
        .whereType<Map>()
        .map((x) => Map<String, dynamic>.from(x))
        .toList(),
  );
  String get displayName => name.isNotEmpty ? name : sender;
  String get body => text.trim().isNotEmpty ? text : plainText(content);
  String get preview => body.replaceAll(RegExp(r'\s+'), ' ').trim();
  String get code => extractOtp(subject, body);
  MailMessage copy({
    bool? unread,
    bool? starred,
    String? folder,
    int? version,
    List<String>? labels,
  }) => MailMessage(
    id: id,
    accountId: accountId,
    version: version ?? this.version,
    subject: subject,
    type: type,
    cc: cc,
    sender: sender,
    name: name,
    to: to,
    text: text,
    content: content,
    time: time,
    folder: folder ?? this.folder,
    unread: unread ?? this.unread,
    starred: starred ?? this.starred,
    labels: labels ?? this.labels,
    attachments: attachments,
  );
  Map<String, dynamic> toJson() => {
    'emailId': id,
    'accountId': accountId,
    'version': version,
    'type': type,
    'cc': cc.split(', ').where((x) => x.isNotEmpty).toList(),
    'subject': subject,
    'sendEmail': sender,
    'name': name,
    'toEmail': to,
    'text': text,
    'content': content,
    'createTime': time,
    'folder': folder,
    'unread': unread ? 0 : 1,
    'isStar': starred ? 1 : 0,
    'labels': labels,
    'attList': attachments,
  };
}

List<dynamic> decodeList(dynamic value) {
  if (value is List) return value;
  if (value is String) {
    try {
      final v = jsonDecode(value);
      if (v is List) return v;
    } catch (_) {}
  }
  return [];
}

class MailDraft {
  final String id;
  int accountId, replyId, revision;
  String to, cc, bcc, subject, body, sendType, requestKey, sendState;
  List<Map<String, dynamic>> attachments;
  MailDraft({
    String? id,
    this.accountId = 0,
    this.replyId = 0,
    this.revision = 0,
    this.to = '',
    this.cc = '',
    this.bcc = '',
    this.subject = '',
    this.body = '',
    this.sendType = '',
    this.requestKey = '',
    this.sendState = '',
    List<Map<String, dynamic>>? attachments,
  }) : id = id ?? newId(),
       attachments = attachments ?? [];
  factory MailDraft.fromJson(Map<String, dynamic> j) => MailDraft(
    id: asText(j['id']),
    accountId: asInt(j['accountId']),
    replyId: asInt(j['replyId']),
    revision: asInt(j['revision']),
    to: asText(j['to']),
    cc: asText(j['cc']),
    bcc: asText(j['bcc']),
    subject: asText(j['subject']),
    body: asText(j['body']),
    sendType: asText(j['sendType']),
    requestKey: asText(j['requestKey']),
    sendState: asText(j['sendState']),
    attachments: decodeList(j['attachments'])
        .whereType<Map>()
        .map((x) => Map<String, dynamic>.from(x))
        .toList(),
  );
  bool get hasContent =>
      [to, cc, bcc, subject, body].any((x) => x.trim().isNotEmpty) ||
      attachments.isNotEmpty;
  bool get outcomeUncertain => [
    'sending',
    'unknown',
    'pending',
    'partial',
    'notSubmitted',
  ].contains(sendState);
  Map<String, dynamic> toJson() => {
    'id': id,
    'accountId': accountId,
    'replyId': replyId,
    'revision': revision,
    'to': to,
    'cc': cc,
    'bcc': bcc,
    'subject': subject,
    'body': body,
    'sendType': sendType,
    'requestKey': requestKey,
    'sendState': sendState,
    'attachments': attachments,
  };
  Map<String, dynamic> sendPayload() => {
    'accountId': accountId,
    'emailId': replyId,
    'sendType': sendType,
    'name': '',
    'manyType': 'together',
    'receiveEmail': parseRecipients(to),
    'ccEmail': parseRecipients(cc),
    'bccEmail': parseRecipients(bcc),
    'subject': subject,
    'text': body,
    'content':
        '<p>${const HtmlEscape().convert(body).replaceAll('\n', '<br>')}</p>',
    'attachments': attachments,
  };
}

class Capabilities {
  final bool organization, safeSend, assistant, draftSync;
  const Capabilities({
    this.organization = false,
    this.safeSend = false,
    this.assistant = false,
    this.draftSync = false,
  });
  factory Capabilities.fromJson(Map<String, dynamic> j) => Capabilities(
    organization: j['organization'] == true,
    safeSend: j['safeSend'] == true,
    assistant: j['assistant'] == true,
    draftSync: j['draftSync'] == true,
  );
}
