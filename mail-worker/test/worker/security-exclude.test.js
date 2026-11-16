import { SELF } from 'cloudflare:test';
import { describe, it, expect } from 'vitest';

describe('security excludes', () => {
	it('rejects /api/testfoo with a JSON 401 envelope', async () => {
		const response = await SELF.fetch('https://example.com/api/testfoo');
		expect(response.status).toBe(200);
		const body = await response.json();
		expect(body.code).toBe(401);
	});
});
