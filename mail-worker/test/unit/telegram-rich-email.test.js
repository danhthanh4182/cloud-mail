import {afterEach, describe, expect, it, vi} from 'vitest';
import {parseHTML} from 'linkedom';
import emailHtmlTemplate from '../../src/template/email-html';
import settingService from '../../src/service/setting-service';
import telegramService from '../../src/service/telegram-service';
import jwtUtils from '../../src/utils/jwt-utils';
import {richEmailBody} from '../../src/utils/telegram-rich-email';

const content = `
<style>.header { color: #d54; }</style>
<table role="presentation"><tr><td>
  <a href="https://shop.example.test/affiliate">
    <img src="https://cdn.example.test/banner.png?a=1&amp;b=2" alt="Cập nhật thông tin thanh toán">
  </a>
  <img src="https://cdn.example.test/pixel.png" width="1" height="1">
  <img src="https://cdn.example.test/logo.png" style="display:none !important">
</td></tr></table>
<p>Chào bạn, hãy cập nhật thông tin.</p>
<table><tr><th>Mục</th><th>Giá</th></tr><tr><td>A</td><td>100</td></tr></table>
<a href="javascript:alert(1)">footer</a>
`;

afterEach(() => {
	vi.restoreAllMocks();
	vi.unstubAllGlobals();
});

function configure(tgMsgText = 'show-images', tgChatId = '-100123') {
	vi.spyOn(settingService, 'query').mockResolvedValue({
		tgChatId, tgMsgText, tgMsgTo: 'hide', tgMsgFrom: 'hide',
		customDomain: 'mail.example.test', tgBotToken: 'fixture',
	});
	vi.spyOn(jwtUtils, 'generateToken').mockResolvedValue('viewer-token');
}

describe('Telegram rich email', () => {
	it('renders the linked banner before the text and preserves a semantic table', () => {
		const result = richEmailBody(content, {showImages: true});
		expect(result).toContain('<img src="https://cdn.example.test/banner.png?a=1&amp;b=2"');
		expect(result).toContain('<a href="https://shop.example.test/affiliate">Cập nhật thông tin thanh toán</a>');
		expect(result).toContain('<table><tr><th>Mục</th><th>Giá</th>');
		expect(result.indexOf('<img')).toBeLessThan(result.indexOf('Chào bạn'));
		expect(result).not.toMatch(/pixel\.png|logo\.png|javascript:|<style|📷/);
		expect(richEmailBody(content)).not.toContain('cdn.example.test');
	});

	it('accepts only HTTPS image URLs, including relative-to-protocol URLs', () => {
		const html = '<img src="//cdn.example.test/a.png"><img src="http://cdn.example.test/b.png">'
			+ '<img src="https://user:secret@cdn.example.test/c.png"><img src="data:image/png;base64,A">';
		expect(richEmailBody(html, {showImages: true})).toBe('<img src="https://cdn.example.test/a.png"/>');
	});

	it('sends rich HTML, keeps one-tap OTP and links to the original email in a group', async () => {
		configure();
		const fetch = vi.fn(async () => Response.json({ok: true}));
		vi.stubGlobal('fetch', fetch);
		await telegramService.sendEmailToBot({}, {emailId: 1, subject: 'Offer', code: '123456', content});
		expect(fetch).toHaveBeenCalledOnce();
		const [url, init] = fetch.mock.calls[0];
		expect(url).toMatch(/\/sendRichMessage$/);
		const payload = JSON.parse(init.body);
		expect(payload.rich_message.html).toContain('<img');
		expect(payload.reply_markup.inline_keyboard).toEqual([
			[{text: 'View original email', url: 'https://mail.example.test/api/telegram/getEmail/viewer-token'}],
			[{text: '123456', copy_text: {text: '123456'}}],
		]);
	});

	it('falls back to one ordinary message on definite rich rejection only', async () => {
		configure('show-images', '123');
		const fetch = vi.fn()
			.mockResolvedValueOnce(Response.json({ok: false, error_code: 400}, {status: 400}))
			.mockResolvedValueOnce(Response.json({ok: true}))
			.mockResolvedValueOnce(new Response(null, {status: 503}));
		vi.stubGlobal('fetch', fetch);
		const message = {emailId: 1, subject: 'Offer', content};
		await telegramService.sendEmailToBot({}, message);
		await telegramService.sendEmailToBot({}, message);
		expect(fetch.mock.calls.map(([url]) => url.split('/').at(-1)))
			.toEqual(['sendRichMessage', 'sendMessage', 'sendRichMessage']);
		const fallback = JSON.parse(fetch.mock.calls[1][1].body);
		expect(fallback.link_preview_options.is_disabled).toBe(true);
		expect(fallback.text).not.toMatch(/<img|📷|cdn\.example\.test/);
		expect(fallback.reply_markup.inline_keyboard[0][0].web_app.url).toContain('viewer-token');
	});

	it('preserves hidden-body and plaintext notification behavior', async () => {
		configure('hide');
		const fetch = vi.fn(async () => Response.json({ok: true}));
		vi.stubGlobal('fetch', fetch);
		await telegramService.sendEmailToBot({}, {emailId: 1, subject: 'Offer', content});
		configure('show');
		await telegramService.sendEmailToBot({}, {emailId: 2, subject: 'Hi', text: 'Plain text'});
		expect(fetch.mock.calls.map(([url]) => url.split('/').at(-1))).toEqual(['sendMessage', 'sendMessage']);
		expect(JSON.parse(fetch.mock.calls[0][1].body).text).not.toContain('Chào bạn');
		expect(JSON.parse(fetch.mock.calls[1][1].body).text).toContain('Plain text');
	});
});

describe('original email viewer', () => {
	it('retains newsletter layout inside a script-disabled frame', () => {
		const rendered = emailHtmlTemplate(`<!doctype html><html lang="vi">
			<head><style>@media (max-width:480px){td{width:100%}}</style></head>
			<body style="background:#fef1de" onload="bad()">
			<table width="600"><tr><td><a href="https://shop.example.test/affiliate"><img
				src="//cdn.example.test/banner.png" onerror="bad()"></a></td></tr></table>
			<script>bad()</script></body></html>`);
		const {document} = parseHTML(rendered);
		const frame = document.querySelector('iframe');
		expect(frame.getAttribute('sandbox')).not.toContain('allow-scripts');
		expect(frame.getAttribute('sandbox')).not.toContain('allow-same-origin');
		const {document: message} = parseHTML(frame.getAttribute('srcdoc'));
		expect(message.documentElement.lang).toBe('vi');
		expect(message.querySelector('head').textContent).toContain('@media (max-width:480px)');
		expect(message.querySelector('table').getAttribute('width')).toBe('600');
		expect(message.querySelector('img').getAttribute('src')).toBe('https://cdn.example.test/banner.png');
		expect(message.querySelector('a').getAttribute('rel')).toBe('noopener noreferrer');
		expect(message.querySelector('script, [onload], [onerror]')).toBeNull();
	});
});
