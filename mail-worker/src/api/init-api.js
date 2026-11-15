import app from '../hono/hono';
import { dbInit } from '../init/init';
import cryptoUtils from '../utils/crypto-utils';

function expectedSecret(c) {
	return c.env.init_secret || c.env.jwt_secret;
}

app.post('/init', async (c) => {
	const secret = expectedSecret(c);
	const provided = c.req.header('X-Init-Secret');
	if (!secret || !cryptoUtils.timingSafeEqualString(provided, secret)) {
		return c.text('unauthorized', 401);
	}
	return dbInit.init(c);
})

app.get('/init/:secret', async (c) => {
	console.warn('GET /init/:secret is deprecated; use POST /init with the X-Init-Secret header');
	const secret = expectedSecret(c);
	if (!secret || !cryptoUtils.timingSafeEqualString(c.req.param('secret'), secret)) {
		return c.text('unauthorized', 401);
	}
	return dbInit.init(c);
})
