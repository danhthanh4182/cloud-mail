import { describe, it, expect } from 'vitest';
import {
	buildContentDisposition,
	hardenObjectResponse,
	parseContentDisposition,
} from '../../src/utils/object-response';

function resp(body, headers) {
	return new Response(body, { headers });
}

describe('object-response', () => {
	it('forces non-allowlisted html to an attachment download', () => {
		const hardened = hardenObjectResponse(
			resp('<script>alert(1)</script>', {
				'Content-Type': 'text/html',
				'Content-Disposition': 'inline; filename="a.html"',
			})
		);
		expect(hardened.headers.get('content-type')).toBe('application/octet-stream');
		const disp = hardened.headers.get('content-disposition');
		expect(disp.startsWith('attachment;')).toBe(true);
		expect(disp).toContain('filename="a.html"');
		expect(hardened.headers.get('x-content-type-options')).toBe('nosniff');
		expect(hardened.headers.get('content-security-policy')).toBe(`sandbox; default-src 'none'`);
	});

	it('preserves allowlisted png inline disposition', () => {
		const hardened = hardenObjectResponse(
			resp('x', {
				'Content-Type': 'image/png; charset=binary',
				'Content-Disposition': 'inline; filename="a.png"',
			})
		);
		expect(hardened.headers.get('content-type')).toBe('image/png; charset=binary');
		expect(hardened.headers.get('content-disposition').startsWith('inline;')).toBe(true);
		expect(hardened.headers.get('x-content-type-options')).toBe('nosniff');
		expect(hardened.headers.get('content-security-policy')).toBe(`sandbox; default-src 'none'`);
	});

	it('keeps svg+xml but sandboxes it', () => {
		const hardened = hardenObjectResponse(resp('<svg/>', { 'Content-Type': 'image/svg+xml' }));
		expect(hardened.headers.get('content-type')).toBe('image/svg+xml');
		expect(hardened.headers.get('content-security-policy')).toBe(`sandbox; default-src 'none'`);
		expect(hardened.headers.get('content-disposition')).toBeNull();
	});

	it('sanitizes hostile filenames without throwing or leaking CR/LF', () => {
		const filename = 'hình "ảnh"\r\n.png';
		let header;
		expect(() => {
			header = buildContentDisposition(filename, 'attachment');
		}).not.toThrow();
		expect(header).not.toMatch(/[\r\n]/);
		expect(header).toContain('filename*=UTF-8\'\'');
		const quoted = header.match(/filename="([^"]*)"/)[1];
		expect(quoted).toMatch(/^[\x20-\x7E]*$/);
		expect(quoted).not.toContain('"');
		const parsed = parseContentDisposition(header);
		expect(parsed).not.toBeNull();
		expect(parsed.type).toBe('attachment');
		expect(() => new Response('x', { headers: { 'Content-Disposition': header } })).not.toThrow();
	});

	it('falls back to the key basename when no disposition exists', () => {
		const hardened = hardenObjectResponse(resp('x', {}), 'attachments/abc.pdf');
		expect(hardened.headers.get('content-type')).toBe('application/octet-stream');
		const disp = hardened.headers.get('content-disposition');
		expect(disp.startsWith('attachment;')).toBe(true);
		expect(disp).toContain('filename="abc.pdf"');
	});

	it('treats the KV "null" disposition as absent', () => {
		expect(parseContentDisposition('null')).toBeNull();
		expect(parseContentDisposition('')).toBeNull();
		expect(parseContentDisposition(null)).toBeNull();
		const hardened = hardenObjectResponse(
			resp('x', { 'Content-Type': 'text/html', 'Content-Disposition': 'null' }),
			'static/probe.html'
		);
		expect(hardened.headers.get('content-disposition')).toContain('filename="probe.html"');
	});
});
