import { exports } from 'cloudflare:workers';
import { describe, it, expect } from 'vitest';
// Transform the Worker before the request's test timeout starts.
import '../../src/index.js';

describe('security excludes', () => {
	it('rejects /api/testfoo with a JSON 401 envelope', async () => {
		const response = await exports.default.fetch('https://example.com/api/testfoo');
		expect(response.status).toBe(200);
		const body = await response.json();
		expect(body.code).toBe(401);
	});
});
