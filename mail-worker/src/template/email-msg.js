import { htmlToTelegram } from '../utils/telegram-html';
import emailUtils from '../utils/email-utils';

const TELEGRAM_MESSAGE_LIMIT = 3500;
const TRUNCATED_SUFFIX = '...';

function escapeHtml(text = '') {
	return text
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;');
}

function truncateText(text, maxLength) {
	if (!text || text.length <= maxLength) {
		return text || '';
	}

	if (maxLength <= TRUNCATED_SUFFIX.length) {
		return TRUNCATED_SUFFIX.slice(0, maxLength);
	}

	return text.slice(0, maxLength - TRUNCATED_SUFFIX.length) + TRUNCATED_SUFFIX;
}

export default function emailMsgTemplate(email, tgMsgTo, tgMsgFrom, tgMsgText, options) {

	let template = `<b>${escapeHtml(email.subject || '')}</b>`

		if (tgMsgFrom === 'only-name') {
			template += `

From\u200B：${escapeHtml(email.name || '')}`
		}

		if (tgMsgFrom === 'show') {
			template += `

From\u200B：${escapeHtml(email.name || '')}  &lt;${escapeHtml(email.sendEmail || '')}&gt;`
		}

		if(tgMsgTo === 'show' && tgMsgFrom === 'hide') {
			template += `

To：\u200B${escapeHtml(email.toEmail || '')}`

		} else if(tgMsgTo === 'show') {
		template += `
To：\u200B${escapeHtml(email.toEmail || '')}`
	}

	const rawText = emailUtils.formatText((email.text || '').replace(/&nbsp;|&#160;|&#x0*a0;|\u00a0/gi, ' '));

	if(tgMsgText === 'show' || tgMsgText === 'show-images') {
		const prefix = `${template}

`;
		const maxTextLength = Math.max(0, TELEGRAM_MESSAGE_LIMIT - prefix.length);
		const body = htmlToTelegram(email.content, maxTextLength, options)
			|| truncateText(escapeHtml(rawText), maxTextLength);
		template += `

${body}`
	}

	return template;

}
