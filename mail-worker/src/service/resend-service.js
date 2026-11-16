import emailService from './email-service';
import { emailConst } from '../const/entity-const';
import cryptoUtils from '../utils/crypto-utils';

const WEBHOOK_TOLERANCE_SECONDS = 300;

function base64ToBytes(value) {
	const binary = atob(value);
	return Uint8Array.from(binary, (ch) => ch.charCodeAt(0));
}

const resendService = {

	async verifyWebhookSignature(c, rawBody, nowSeconds = Math.floor(Date.now() / 1000)) {

		const id = c.req.header('svix-id');
		const timestamp = c.req.header('svix-timestamp');
		const signature = c.req.header('svix-signature');

		if (!id || !timestamp || !signature) {
			return false;
		}

		const secret = c.env?.resend_webhook_secret;
		if (!secret || !secret.startsWith('whsec_')) {
			console.error('resend webhook: resend_webhook_secret is missing or malformed');
			return false;
		}

		let keyBytes;
		try {
			keyBytes = base64ToBytes(secret.slice('whsec_'.length));
		} catch {
			console.error('resend webhook: resend_webhook_secret is not valid base64');
			return false;
		}

		const ts = Number.parseInt(timestamp, 10);
		if (!Number.isFinite(ts) || Math.abs(nowSeconds - ts) > WEBHOOK_TOLERANCE_SECONDS) {
			return false;
		}

		const signed = `${id}.${ts}.${rawBody}`;
		const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
		const expected = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(signed)));

		for (const entry of signature.split(' ')) {
			if (!entry.startsWith('v1,')) {
				continue;
			}
			let candidate;
			try {
				candidate = base64ToBytes(entry.slice(3));
			} catch {
				continue;
			}
			if (cryptoUtils.timingSafeEqualBytes(expected, candidate)) {
				return true;
			}
		}

		return false;
	},

	async webhooks(c, body) {

		const params = {
			resendEmailId: body.data.email_id,
			status: emailConst.status.SENT
		}

		if (body.type === 'email.delivered') {
			params.status = emailConst.status.DELIVERED
			params.message = null
		}

		if (body.type === 'email.complained') {
			params.status = emailConst.status.COMPLAINED
			params.message = null
		}

		if (body.type === 'email.bounced') {
			let bounce = body.data.bounce
			bounce = JSON.stringify(bounce);
			params.status = emailConst.status.BOUNCED
			params.message = bounce
		}

		if (body.type === 'email.delivery_delayed') {
			params.status = emailConst.status.DELAYED
			params.message = null
		}

		if (body.type === 'email.failed') {
			params.status = emailConst.status.FAILED
			params.message = body.data.failed.reason
		}

		const emailRow = await emailService.updateEmailStatus(c, params)

		if (!emailRow) {
			// 未知邮件事件（如历史数据、重复投递、测试事件）：记录日志后正常返回，
			// 避免 Resend 因连续收到 500 而熔断关闭 Webhook
			console.warn(`resend webhook: unknown email_id ${params.resendEmailId}, type ${body.type}`);
			return;
		}

	}
}

export default resendService
