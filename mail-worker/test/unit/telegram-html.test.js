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

	it('keeps plain-text path unchanged', () => {
		const msg = emailMsgTemplate(
			{ subject: 'Hi', name: '', sendEmail: '', toEmail: '', text: 'a <b> b', content: '<p>ignored</p>' },
			'hide', 'hide', 'show'
		);
		expect(msg).toContain('a &lt;b&gt; b');
		expect(msg).not.toContain('ignored');
	});
});
