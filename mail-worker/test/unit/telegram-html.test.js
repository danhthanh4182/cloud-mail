import { describe, it, expect } from 'vitest';
import { htmlToTelegram } from '../../src/utils/telegram-html';
import emailMsgTemplate from '../../src/template/email-msg';

describe('htmlToTelegram', () => {
	it('renders headings bold and paragraphs separated', () => {
		const out = htmlToTelegram('<h1>Sale 50%</h1><p>Deal one</p><p>Deal two</p>');
		expect(out).toContain('<b>Sale 50%</b>');
		expect(out).toContain('Deal one\n\nDeal two');
	});

	it('keeps safe links clickable and drops unsafe hrefs', () => {
		const out = htmlToTelegram('<a href="https://x.test/d?a=1&b=2">Shop</a> <a href="javascript:alert(1)">bad</a>');
		expect(out).toContain('<a href="https://x.test/d?a=1&amp;b=2">Shop</a>');
		expect(out).toContain('bad');
		expect(out).not.toContain('javascript:');
	});

	it('preserves literal tag-like link text instead of stripping it as markup', () => {
		const out = htmlToTelegram('<a href="https://x.test">Use &lt;b&gt; literally &amp; safely</a>');
		expect(out).toBe('<a href="https://x.test">Use &lt;b&gt; literally &amp; safely</a>');
	});

	it('flattens formatted link labels without reconstructing injected markup', () => {
		const out = htmlToTelegram('<a href="https://x.test"><strong>Read</strong><br><span>&lt;scrip&lt;b&gt;t&gt;</span><img src="https://x.test/i.png" alt="Banner"></a>');
		expect(out).toBe('<a href="https://x.test">Read &lt;scrip&lt;b&gt;t&gt;📷 Banner</a>');
	});

	it('removes trailing table separators while preserving interior pipes and new lines', () => {
		const out = htmlToTelegram('<div>left | right | | </div><div>next | row |</div>');
		expect(out).toBe('left | right\n\nnext | row');
	});

	it('handles long pipe-rich lines without excessive backtracking', () => {
		const text = '| '.repeat(1200) + 'end';
		expect(htmlToTelegram(`<p>${text}</p>`)).toBe(text);
	}, 5000);

	it('renders lists with markers and numbering', () => {
		const out = htmlToTelegram('<ul><li>a</li><li>b</li></ul><ol><li>x</li><li>y</li></ol>');
		expect(out).toContain('• a');
		expect(out).toContain('1. x');
		expect(out).toContain('2. y');
	});

	it('renders images as linked placeholders', () => {
		const out = htmlToTelegram('<img src="https://x.test/i.png" alt="Banner">');
		expect(out).toContain('<a href="https://x.test/i.png">📷 Banner</a>');
	});

	it('renders code and quotes with telegram tags', () => {
		const out = htmlToTelegram('<p>code <code>061162</code></p><blockquote>note</blockquote><pre>line1\nline2</pre>');
		expect(out).toContain('<code>061162</code>');
		expect(out).toContain('<blockquote>note</blockquote>');
		expect(out).toContain('<pre>line1\nline2</pre>');
	});

	it('strips scripts and escapes text', () => {
		const out = htmlToTelegram('<script>alert(1)</script><p>fish &amp; chips &lt;3 you</p>');
		expect(out).not.toContain('alert(1)');
		expect(out).toContain('fish &amp; chips &lt;3 you');
	});
	it('wraps standalone otp-like codes in code tags', () => {
		expect(htmlToTelegram('<div><span>061162</span></div>')).toContain('<code>061162</code>');
		expect(htmlToTelegram('<p>GIAM</p>')).not.toContain('<code>');
	});

	it('separates blocks that follow inline content', () => {
		const out = htmlToTelegram('<img src="https://x.test/i.png" alt="Banner"><h2>Title</h2>');
		expect(out).toContain('</a>\n\n<b>Title</b>');
	});

	it('truncates within budget without broken tags', () => {
		const long = `<p>${'word '.repeat(2000)}</p><a href="https://x.test/very/long">link</a>`;
		const out = htmlToTelegram(long, 500);
		expect(out.length).toBeLessThanOrEqual(503);
		expect(out.endsWith('...')).toBe(true);
		expect(out).not.toMatch(/<[^>]*$/);
		expect(out).not.toContain('</a');
	});

	it('returns empty string for empty input', () => {
		expect(htmlToTelegram('')).toBe('');
		expect(htmlToTelegram(null)).toBe('');
	});
});

describe('emailMsgTemplate with html body', () => {
	it('embeds rich telegram markup for html emails', () => {
		const msg = emailMsgTemplate(
			{ subject: 'Sale', name: 'S', sendEmail: 's@x.test', toEmail: 'me@x.test', text: '', content: '<h2>Deal</h2><p><a href="https://x.test/buy">Buy now</a></p>' },
			'show', 'show', 'show'
		);
		expect(msg).toContain('<b>Sale</b>');
		expect(msg).toContain('<b>Deal</b>');
		expect(msg).toContain('<a href="https://x.test/buy">Buy now</a>');
	});

	it('prefers HTML paragraphs when plain text is flattened and entity encoded', () => {
		const msg = emailMsgTemplate({ subject: 'Domain offer', text: 'Hello,&nbsp;I noticed you own example.com.Kind regards,Sender', content: '<p>Hello,&nbsp;I noticed you own example.com.</p><p>Kind regards,<br>Sender</p>' }, 'hide', 'hide', 'show');
		expect(msg).toContain('Hello, I noticed you own example.com.\n\nKind regards,\nSender');
		expect(msg).not.toContain('&amp;nbsp;');
	});

	it('normalizes encoded and literal nonbreaking spaces in text-only emails', () => {
		const msg = emailMsgTemplate({ subject: 'Hello', text: 'Hello,&nbsp;there\u00a0friend' }, 'hide', 'hide', 'show');
		expect(msg).toContain('Hello, there friend');
	});

	it('falls back to plain text when HTML has no visible content', () => {
		const msg = emailMsgTemplate({ subject: 'Notice', text: 'Readable text', content: '<style>p{color:red}</style>' }, 'hide', 'hide', 'show');
		expect(msg).toContain('Readable text');
	});

	it('keeps plain-text path unchanged', () => {
		const msg = emailMsgTemplate(
			{ subject: 'Hi', name: '', sendEmail: '', toEmail: '', text: 'a <b> b', content: '' },
			'hide', 'hide', 'show'
		);
		expect(msg).toContain('a &lt;b&gt; b');
		expect(msg).not.toContain('ignored');
	});
});
