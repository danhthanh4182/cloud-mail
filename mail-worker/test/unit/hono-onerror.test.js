import { describe, it, expect, vi, beforeEach } from 'vitest';
import BizError from '../../src/error/biz-error';
import { onErrorHandler } from '../../src/hono/hono';

function fakeContext() {
	const seen = [];
	return {
		seen,
		json: (body) => {
			seen.push(body);
			return { status: 200, body };
		},
	};
}

describe('onErrorHandler', () => {
	beforeEach(() => {
		vi.restoreAllMocks();
	});

	it('hides internal messages behind a request id', () => {
		const err = vi.spyOn(console, 'error').mockImplementation(() => {});
		const c = fakeContext();

		onErrorHandler(new Error('secret db failure'), c);

		expect(c.seen).toHaveLength(1);
		expect(c.seen[0].message).toMatch(/^Internal error \(.+\)$/);
		expect(c.seen[0].message).not.toContain('secret db failure');
		expect(err).toHaveBeenCalledTimes(1);
		expect(err.mock.calls[0].join(' ')).toContain(c.seen[0].message.match(/\((.+)\)/)[1]);
	});

	it('keeps BizError envelopes untouched', () => {
		const c = fakeContext();
		onErrorHandler(new BizError('x', 403), c);
		expect(c.seen).toEqual([{ code: 403, message: 'x' }]);
	});
});
