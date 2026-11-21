# Cloud Mail Design System · proposal 1

## Design intent
An Android email workspace with calm hierarchy: quiet neutral surfaces, one cobalt action color, clear unread typography and a dedicated copy action for verification codes. Familiar email organization without copying Gmail branding. Official Material 3 widgets will be the Flutter implementation foundation; the HTML is an illustrative prototype, not an official Material package or implemented APK screen.

## Semantic tokens
| Role | Light | Dark |
|---|---|---|
| background | #F4F6FA | #11141B |
| surface | #FFFFFF | #1B202A |
| surfaceMuted | #EDF1F7 | #242B37 |
| textPrimary | #17233B | #F0F3FA |
| textSecondary | #5C6880 | #B2BDD1 |
| outline | #DEE4EF | #3F4B60 |
| primary | #2458D3 | #AFC6FF |
| onPrimary | #FFFFFF | #102B67 |
| primaryContainer | #EAF0FF | #203358 |
| success | #18714B | #8AD8B0 |
| error | #B3261E | #FFB4AB |
| unreadMarker | #2458D3 | #AFC6FF |

Never use unread color alone: sender/subject weight and semantics also identify unread state. Decorative avatar colors have no status meaning. Validate actual component contrast, not just raw palette pairs.

## Typography
Flutter uses a bundled Vietnamese-capable sans font (Roboto/Noto Sans after license verification), system fallbacks for the HTML. Scale: display32/40 weight600; title28/36 weight650; section20/28 weight600; body16/24 weight400; label14/20 weight500; metadata12/16 weight500. OTP uses tabular numerals 28/36 with 2px tracking; do not make numbers unselectable. System font scaling remains enabled, layout expands rather than clipping essential actions.

## Geometry and motion
Spacing scale 4,8,12,16,20,24,32,40; default mobile inset20; list row min88; touch target48; icons22/24. Radius: fields12, cards20, sheets28, pills/full for chips and FAB. Flat mail list with subtle separators; elevation only for floating actions/sheets. Motion: pressed80ms, state160ms, screen240ms. Reduced-motion uses immediate transitions. No looping decorative animations.

## Components and variants
| Component | Required variants/states | Behavior |
|---|---|---|
| AppBar/SearchField | default/focused/query/loading | search scope visible, clear accessible |
| MailListItem | unread/read/starred/selected/attachment | sender,subject,preview,time; row action labels |
| OtpCard | validated/ambiguous/copied/expired-known | copy only source-validated code; never invented expiry |
| FolderChip | selected/unselected/count | count explained as server total or local subset |
| BottomNavigation | Inbox/Starred/Drafts/Settings | text labels retained; active pill and semantic selected |
| ComposeFAB | collapsed/extended | bottom safe-area aware, never covers final row |
| SummaryPanel | loading/ready/error/disabled | identifies generated text and opens source |
| AttachmentTile | upload/download/progress/error | cancel/retry, size/name and file availability |
| RecipientChip/Input | valid/invalid/duplicate | To/CC/BCC stay explicit |
| PrimaryButton | default/pressed/focus/disabled/loading | label unchanged; prevent duplicate send |
| StatusBanner | offline/stale/error/syncing | shows cause and recovery action |
| EmptyState | no mail/no results/no connection | distinct copy and relevant next action |
| ConfirmSheet | send/delete/logout | actionable consequence; destructive action never implied by color only |

## Screen inventory
S01 server/login; S02 unified inbox; S03 address/folder picker; S04 search/results; S05 reader/thread; S06 OTP action; S07 composer; S08 draft list/recovery; S09 attachment manager; S10 settings/profile; S11 labels/spam/trash; S12 assistant preferences/corrections. Skeleton/error/empty/offline are variants, not omitted screens.

## Adaptive and accessible behavior
360–599 logical px: single pane, bottom navigation, full-screen reader. 600–839: navigation rail, optional list/detail depending text scaling. >=840: rail + list/detail, compose as pane/sheet. Respect system bars/IME. TalkBack order: heading, sender, key actions, summary, original body, attachments. Label icon buttons; announce copy/save/error without reading OTP on locked notifications. Interactive icons >=48dp target even when drawn22px. No horizontal scrolling of forms at200% font scale.

## Prototype guide and honest boundaries
`mockup.html`: desktop design board; switch Phác thảo / Mockup / Design system; dark toggle; individual phones support search, filters, opening mail, local star, composer and simulated send confirmation. All data is fictional; no live API, no actual email sending. Copy is only of a sample code. Mockup screenshot is not a capture of an APK.

Phosphor regular SVG icons are embedded from @phosphor-icons/core2.1.1, MIT (license copied). App implementation will use a single compatible icon family with recorded attribution.
