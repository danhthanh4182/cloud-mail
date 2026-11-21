import orm from '../entity/orm';
import email from '../entity/email';
import settingService from './setting-service';
import dayjs from 'dayjs';
import utc from 'dayjs/plugin/utc';
import timezone from 'dayjs/plugin/timezone';
dayjs.extend(utc);
dayjs.extend(timezone);
import { eq } from 'drizzle-orm';
import jwtUtils from '../utils/jwt-utils';
import emailMsgTemplate from '../template/email-msg';
import emailTextTemplate from '../template/email-text';
import emailHtmlTemplate from '../template/email-html';
import verifyUtils from '../utils/verify-utils';
import domainUtils from '../utils/domain-uitls';
import {richEmailBody, safeEmailUrl} from '../utils/telegram-rich-email';

const telegramService = {

	async getEmailContent(c, params) {

		const { token } = params

		const result = await jwtUtils.verifyToken(c, token);

		if (!result || result.aud !== 'tg-view') {
			return emailTextTemplate('Access denied')
		}

		const emailRow = await orm(c).select().from(email).where(eq(email.emailId, result.emailId)).get();

		if (emailRow) {

			if (emailRow.content) {
				const { r2Domain } = await settingService.query(c);
				return emailHtmlTemplate(emailRow.content || '', r2Domain)
			} else {
				return emailTextTemplate(emailRow.text || '')
			}

		} else {
			return emailTextTemplate('The email does not exist')
		}

	},

	async sendEmailToBot(c, email) {

		const { tgBotToken, tgChatId, customDomain, tgMsgTo, tgMsgFrom, tgMsgText } = await settingService.query(c);

		const tgChatIds = tgChatId.split(',').map(id => id.trim()).filter(Boolean);
		const origin = safeEmailUrl(domainUtils.toOssDomain(customDomain), true)?.replace(/\/$/, '');
		const viewerUrl = origin
			? `${origin}/api/telegram/getEmail/${await jwtUtils.generateToken(c, {emailId: email.emailId, aud: 'tg-view'}, 7 * 24 * 3600)}`
			: null;
		let body = '';
		if (tgMsgText === 'show' || tgMsgText === 'show-images') {
			try {
				body = richEmailBody(email.content, {showImages: tgMsgText === 'show-images'});
			} catch {
				console.error('Could not format Telegram rich notification');
			}
		}
		const notification = {...email, subject: email.subject || '(No subject)'};
		const header = emailMsgTemplate(notification, tgMsgTo, tgMsgFrom, 'hide').trim();
		const plain = emailMsgTemplate(notification, tgMsgTo, tgMsgFrom, tgMsgText, {omitImages: true});

		async function send(method, payload) {
			const response = await fetch(`https://api.telegram.org/bot${tgBotToken}/${method}`, {
				method: 'POST',
				headers: {'Content-Type': 'application/json'},
				body: JSON.stringify(payload),
			});
			return response.status;
		}

		await Promise.all(tgChatIds.map(async chatId => {
			const inlineKeyboard = [];
			if (viewerUrl) {
				const view = {text: 'View original email'};
				// Telegram Mini App buttons are available only in private bot chats.
				if (/^\d+$/.test(chatId)) view.web_app = {url: viewerUrl};
				else view.url = viewerUrl;
				inlineKeyboard.push([view]);
			}
			if (email.code) {
				inlineKeyboard.push([{text: email.code, copy_text: {text: email.code}}]);
			}
			const common = {
				chat_id: chatId,
				...(inlineKeyboard.length && {reply_markup: {inline_keyboard: inlineKeyboard}}),
			};
			try {
				if (body) {
					const status = await send('sendRichMessage', {
						...common,
						rich_message: {html: `<p>${header.replace(/\r?\n/g, '<br>')}</p>\n${body}`},
					});
					if (status >= 200 && status < 300) return;
					// Only retry a different format if Telegram rejected the request.
					if (![400, 403, 404].includes(status)) {
						console.error('Telegram rich notification failed', status);
						return;
					}
				}
				const status = await send('sendMessage', {
					...common,
					parse_mode: 'HTML',
					text: plain.trim() || 'New email',
					link_preview_options: {is_disabled: true},
				});
				if (status >= 300) console.error('Telegram notification failed', status);
			} catch {
				// A network error can occur after delivery. Avoid a duplicate message.
				console.error('Telegram notification delivery status is unknown');
			}
		}));

	}

}

export default telegramService
