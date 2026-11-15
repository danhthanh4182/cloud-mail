import { describe, it, expect } from 'vitest';
import reqUtils from '../../src/utils/req-utils';

function fakeContext(userAgent) {
	return {
		req: {
			header: (name) => (name.toLowerCase() === 'user-agent' ? userAgent : undefined),
		},
	};
}

describe('req-utils getUserAgent', () => {
	it('parses Android Chrome UA', () => {
		const ua =
			'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
		const result = reqUtils.getUserAgent(fakeContext(ua));
		expect(result.os).toContain('Android');
		expect(result.browser).toContain('Chrome');
	});

	it('returns empty strings and Desktop for missing UA', () => {
		const result = reqUtils.getUserAgent(fakeContext(undefined));
		expect(result).toEqual({ browser: '', os: '', device: 'Desktop' });
	});
});
