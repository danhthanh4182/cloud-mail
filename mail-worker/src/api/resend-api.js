import resendService from '../service/resend-service';
import app from '../hono/hono';

let warned = false;

app.post('/webhooks', async (c) => {
	const rawBody = await c.req.text();

	if (!c.env?.resend_webhook_secret) {
		if (!warned) {
			warned = true;
			console.warn('resend webhook: resend_webhook_secret is not set, signature verification is disabled');
		}
		try {
			await resendService.webhooks(c, JSON.parse(rawBody));
			return c.text('success', 200)
		} catch (e) {
			return c.text(e.message, 500)
		}
	}

	if (!await resendService.verifyWebhookSignature(c, rawBody)) {
		return c.text('unauthorized', 401)
	}

	let body;
	try {
		body = JSON.parse(rawBody);
	} catch {
		return c.text('bad request', 400)
	}

	if (!body?.data?.email_id) {
		return c.text('bad request', 400)
	}

	try {
		await resendService.webhooks(c, body);
		return c.text('success', 200)
	} catch (e) {
		console.error(e);
		return c.text('error', 500)
	}
})
