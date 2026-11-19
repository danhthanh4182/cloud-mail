import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
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

class MailParticipant {
  final String address, name;
  const MailParticipant(this.address, {this.name = ''});

  String get displayName => name.isEmpty ? address : name;

  Map<String, String> toJson() => {'address': address, 'name': name};

  static List<MailParticipant> read(dynamic source) => [
    for (final item in decodeList(source))
      if (item is Map && asText(item['address']).trim().isNotEmpty)
        MailParticipant(
          asText(item['address']).trim(),
          name: asText(item['name']).trim(),
        )
      else if (item is String && item.trim().isNotEmpty)
        MailParticipant(item.trim()),
  ];

  static List<MailParticipant> addresses(String value) => [
    for (final address in value.split(','))
      if (address.trim().isNotEmpty) MailParticipant(address.trim()),
  ];
}

class MailMessage {
  final int id, accountId, version, type;
  final String subject, sender, name, to, text, content, time, folder, cc;
  final bool unread, starred, senderDomainAuthenticated;
  final String category, reason;
  final List<String> labels;
  final List<MailParticipant> recipients, copiedRecipients;
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
    this.category = '',
    this.reason = '',
    this.unread = true,
    this.starred = false,
    this.senderDomainAuthenticated = false,
    this.labels = const [],
    this.recipients = const [],
    this.copiedRecipients = const [],
    this.attachments = const [],
  });
  factory MailMessage.fromJson(Map<String, dynamic> j) {
    final recipients = MailParticipant.read(j['recipient']);
    final copiedRecipients = MailParticipant.read(j['cc']);
    return MailMessage(
      id: asInt(j['emailId']),
      accountId: asInt(j['accountId']),
      version: asInt(j['version']),
      type: asInt(j['type']),
      cc: copiedRecipients.map((person) => person.address).join(', '),
      subject: asText(j['subject']),
      sender: asText(j['sendEmail']),
      name: asText(j['name']),
      to: recipients.isNotEmpty
          ? recipients.map((person) => person.address).join(', ')
          : asText(j['toEmail']),
      text: asText(j['text']),
      content: asText(j['content']),
      time: asText(j['createTime']),
      folder: asText(j['folder']).isEmpty ? 'inbox' : asText(j['folder']),
      category: asText(j['category']),
      reason: asText(j['reason']),
      unread: asInt(j['unread']) == 0,
      starred: asInt(j['isStar']) == 1 || j['starId'] != null,
      senderDomainAuthenticated: j['senderDomainAuthenticated'] == true,
      recipients: recipients,
      copiedRecipients: copiedRecipients,
      labels: decodeList(j['labels']).map((x) => '$x').toList(),
      attachments: decodeList(j['attList'])
          .whereType<Map>()
          .map((x) => Map<String, dynamic>.from(x))
          .toList(),
    );
  }
  String get displayName => name.isNotEmpty ? name : sender;
  List<MailParticipant> get toPeople =>
      recipients.isEmpty ? MailParticipant.addresses(to) : recipients;
  List<MailParticipant> get ccPeople => copiedRecipients.isEmpty
      ? MailParticipant.addresses(cc)
      : copiedRecipients;
  String? get authenticatedDomain {
    final at = sender.lastIndexOf('@');
    if (!senderDomainAuthenticated || type != 0 || at < 1) return null;
    final domain = sender.substring(at + 1).trim().toLowerCase();
    return domain.isEmpty ? null : domain;
  }

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
    category: category,
    reason: reason,
    cc: cc,
    recipients: recipients,
    copiedRecipients: copiedRecipients,
    sender: sender,
    name: name,
    to: to,
    text: text,
    content: content,
    time: time,
    folder: folder ?? this.folder,
    unread: unread ?? this.unread,
    starred: starred ?? this.starred,
    senderDomainAuthenticated: senderDomainAuthenticated,
    labels: labels ?? this.labels,
    attachments: attachments,
  );
  Map<String, dynamic> toJson() => {
    'emailId': id,
    'accountId': accountId,
    'version': version,
    'type': type,
    'category': category,
    'reason': reason,
    'cc': ccPeople.map((person) => person.toJson()).toList(),
    'recipient': toPeople.map((person) => person.toJson()).toList(),
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
    'senderDomainAuthenticated': senderDomainAuthenticated,
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
  int accountId, replyId, revision, missingAttachments;
  String syncStamp;
  bool conflictCopy;
  String to, cc, bcc, subject, body, sendType, requestKey, sendState;
  List<Map<String, dynamic>> attachments;
  MailDraft({
    String? id,
    this.accountId = 0,
    this.replyId = 0,
    this.revision = 0,
    this.syncStamp = '',
    this.conflictCopy = false,
    this.missingAttachments = 0,
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
    syncStamp: asText(j['syncStamp']),
    conflictCopy: j['conflictCopy'] == true,
    missingAttachments: asInt(j['missingAttachments']),
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
    'conflict',
  ].contains(sendState);
  Map<String, dynamic> toJson() => {
    'id': id,
    'accountId': accountId,
    'replyId': replyId,
    'revision': revision,
    'syncStamp': syncStamp,
    'conflictCopy': conflictCopy,
    'missingAttachments': missingAttachments,
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
  final bool organization,
      safeSend,
      assistant,
      draftSync,
      conversation,
      smartMail,
      push;
  const Capabilities({
    this.organization = false,
    this.safeSend = false,
    this.assistant = false,
    this.draftSync = false,
    this.conversation = false,
    this.smartMail = false,
    this.push = false,
  });
  Map<String, dynamic> toJson() => {
    'version': 2,
    'organization': organization,
    'safeSend': safeSend,
    'assistant': assistant,
    'draftSync': draftSync,
    'conversation': conversation,
    'smartMail': smartMail,
    'push': push,
  };
  factory Capabilities.fromJson(Map<String, dynamic> j) => Capabilities(
    organization: j['organization'] == true,
    safeSend: j['safeSend'] == true,
    assistant: j['assistant'] == true,
    draftSync: asInt(j['version']) >= 2 && j['draftSync'] == true,
    conversation: j['conversation'] == true,
    smartMail: j['smartMail'] == true,
    push: j['push'] == true,
  );
}

/// Canonical payload identity shared by send and reconciliation.
String sendPayloadHash(Map<String, dynamic> payload) {
  Object? canonical(Object? value) {
    if (value is Map<String, dynamic>) {
      final keys = value.keys.toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList();
    return value;
  }

  return sha256.convert(utf8.encode(jsonEncode(canonical(payload)))).toString();
}
