export const INLINE_MIME_ALLOWLIST = [
	/^image\/(png|jpeg|gif|webp|avif|bmp|x-icon|vnd\.microsoft\.icon|svg\+xml)$/,
	/^video\/(mp4|webm)$/,
];

export function sanitizeFilename(name) {
	const flat = String(name ?? '').replace(/[\x00-\x1F\x7F"\\]/g, '_');
	let ascii = '';
	for (const ch of flat) {
		const code = ch.codePointAt(0);
		ascii += code >= 0x20 && code <= 0x7e ? ch : '_';
	}
	return ascii === '' ? 'download' : ascii;
}

function encodeRFC5987(value) {
	return encodeURIComponent(value).replace(/['()*]/g, (ch) =>
		'%' + ch.charCodeAt(0).toString(16).toUpperCase()
	);
}

export function buildContentDisposition(filename, type) {
	const disposition = type === 'inline' ? 'inline' : 'attachment';
	const fallback = sanitizeFilename(filename);
	return `${disposition}; filename="${fallback}"; filename*=UTF-8''${encodeRFC5987(String(filename ?? ''))}`;
}

export function parseContentDisposition(value) {
	if (value === null || value === undefined) {
		return null;
	}
	const header = String(value).trim();
	if (header === '') {
		return null;
	}
	const lower = header.toLowerCase();
	const hasType = lower.includes('inline') || lower.includes('attachment');
	const starMatch = header.match(/filename\*\s*=\s*UTF-8''([^;]*)/i);
	const quotedMatch = header.match(/filename\s*=\s*"([^"]*)"/i);
	const bareMatch = header.match(/filename\s*=\s*([^;,\s"]+)/i);
	const filenameMatch = starMatch || quotedMatch || bareMatch;
	if (!hasType && !filenameMatch) {
		return null;
	}
	let filename = '';
	if (starMatch) {
		try {
			filename = decodeURIComponent(starMatch[1].trim());
		} catch {
			filename = '';
		}
	} else if (filenameMatch) {
		filename = filenameMatch[1].trim();
	}
	const type = lower.startsWith('inline') ? 'inline' : 'attachment';
	return { type, filename };
}

function keyBasename(key) {
	try {
		const base = String(key ?? '').split('/').pop();
		if (!base) {
			return '';
		}
		try {
			return decodeURIComponent(base);
		} catch {
			return base;
		}
	} catch {
		return '';
	}
}

export function hardenObjectResponse(resp, key = '') {
	if (!resp) {
		return null;
	}
	const headers = new Headers(resp.headers);
	const rawType = headers.get('content-type') || '';
	const mime = rawType.split(';')[0].trim().toLowerCase();
	const allowlisted = INLINE_MIME_ALLOWLIST.some((re) => re.test(mime));

	if (allowlisted) {
		const parsed = parseContentDisposition(headers.get('content-disposition'));
		if (parsed) {
			headers.set('Content-Disposition', buildContentDisposition(parsed.filename, parsed.type));
		} else {
			headers.delete('Content-Disposition');
		}
	} else {
		const parsed = parseContentDisposition(headers.get('content-disposition'));
		const filename = parsed?.filename || keyBasename(key) || 'download';
		headers.set('Content-Type', 'application/octet-stream');
		headers.set('Content-Disposition', buildContentDisposition(filename, 'attachment'));
	}

	headers.set('X-Content-Type-Options', 'nosniff');
	headers.set('Content-Security-Policy', `sandbox; default-src 'none'`);

	return new Response(resp.body, {
		status: resp.status,
		statusText: resp.statusText,
		headers,
	});
}
