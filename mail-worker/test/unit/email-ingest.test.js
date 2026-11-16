import { describe, it, expect } from 'vitest';
import { parseRawEmail, checkBlock } from '../../src/email/email';

function streamOf(chunks) {
	return new ReadableStream({
		start(controller) {
			for (const chunk of chunks) controller.enqueue(chunk);
			controller.close();
		},
	});
}

describe('email ingest', () => {
	it('parses bytes split mid-character', async () => {
		const full = new TextEncoder().encode('Subject: t\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n€');
		const splitAt = full.indexOf(0xe2) + 1;
		const message = { raw: streamOf([full.slice(0, splitAt), full.slice(splitAt)]) };

		const parsed = await parseRawEmail(message);
		expect(parsed.text.trim()).toBe('€');
	});

	it('matches blacklists after normalization', () => {
		expect(checkBlock('a,b,', '', '', { subject: 'hello', html: '', text: '' })).toBe(false);
		expect(checkBlock('a,b,', '', '', { subject: 'a', html: '', text: '' })).toBe(true);
	});

	it('tolerates a missing from address', () => {
		expect(() => checkBlock('', '', 'x', { subject: '', html: '', text: '' })).not.toThrow();
		expect(checkBlock('', '', 'x', { subject: '', html: '', text: '' })).toBe(false);
	});
});
