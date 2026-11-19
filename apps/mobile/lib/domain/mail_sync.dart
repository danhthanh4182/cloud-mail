import 'dart:convert';

import 'mail.dart';

/// Stores only text and an attachment count on the draft replica.
Map<String, dynamic> draftReplica(MailDraft draft) => {
  'id': draft.id,
  'accountId': draft.accountId,
  'replyId': draft.replyId,
  'sendType': draft.sendType,
  'to': draft.to,
  'cc': draft.cc,
  'bcc': draft.bcc,
  'subject': draft.subject,
  'body': draft.body,
  'attachmentCount': draft.missingAttachments + draft.attachments.length,
};

String draftStamp(MailDraft draft) => jsonEncode(draftReplica(draft));

/// A changed local draft must survive both remote edits and remote deletion.
bool draftChanged(MailDraft draft) =>
    draft.revision == 0 || draft.syncStamp != draftStamp(draft);

class PendingMailEdit {
  final int emailId;
  final Map<String, dynamic> patch;
  final bool conflict;
  const PendingMailEdit(this.emailId, this.patch, {this.conflict = false});

  factory PendingMailEdit.fromJson(Map<String, dynamic> json) =>
      PendingMailEdit(
        asInt(json['emailId']),
        Map<String, dynamic>.from(json['patch'] as Map),
        conflict: json['conflict'] == true,
      );

  Map<String, dynamic> toJson() => {
    'emailId': emailId,
    'patch': patch,
    'conflict': conflict,
  };

  MailMessage apply(MailMessage message) => message.copy(
    folder: patch['folder'] as String?,
    labels: (patch['labels'] as List?)?.cast<String>(),
    unread: patch['read'] is bool ? !(patch['read'] as bool) : null,
  );
}
