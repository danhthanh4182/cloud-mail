import {parseHTML} from 'linkedom';

const OMIT = new Set(['head', 'style', 'script', 'noscript', 'template', 'iframe',
	'object', 'embed', 'svg', 'math', 'input', 'textarea', 'select', 'title']);
const BLOCK = /^(?:p|div|section|article|header|footer|main|aside|figure|figcaption|form|blockquote|pre|h[1-6]|ul|ol|li|table|thead|tbody|tfoot|tr|td|th)$/;
const INLINE = new Map([
	['b', 'b'], ['strong', 'b'], ['i', 'i'], ['em', 'i'], ['u', 'u'], ['ins', 'u'],
	['s', 's'], ['strike', 's'], ['del', 's'], ['code', 'code'],
]);
const MAX_BLOCKS = 140;
const MAX_IMAGES = 12;
const MAX_HTML = 24000;

export function escapeTelegramHtml(value) {
	return String(value ?? '').replace(/[&<>"\u0000]/g, ch => ({
		'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', '\u0000': '',
	})[ch]);
}

export function safeEmailUrl(value, image = false) {
	const input = value?.trim() || '';
	if (input.length > 2048) return null;
	try {
		const url = new URL(input.startsWith('//') ? `https:${input}` : input);
		if (url.username || url.password) return null;
		if (url.protocol === 'https:' || (!image && url.protocol === 'http:')) return url.href;
		if (!image && /^(mailto:|tel:)$/.test(url.protocol) && url.pathname) return url.href;
	} catch {
		// Missing or unsupported URL.
	}
	return null;
}

function hidden(node) {
	const style = node.getAttribute('style') || '';
	return node.hasAttribute('hidden') ||
		/(?:^|;)\s*(?:display\s*:\s*none|visibility\s*:\s*hidden|mso-hide\s*:\s*all)\s*(?:!important\s*)?(?:;|$)/i.test(style);
}

function tinyImage(node) {
	const style = node.getAttribute('style') || '';
	return ['width', 'height'].some(name => {
		const size = node.getAttribute(name);
		const dimension = new RegExp(`(?:^|;)\\s*${name}\\s*:\\s*(?:0|1)(?:\\.0+)?px\\s*(?:!important\\s*)?(?:;|$)`, 'i');
		return (size?.trim() && /^(?:0|1)(?:px)?$/i.test(size.trim())) || dimension.test(style);
	});
}

function dataRows(table) {
	if (['presentation', 'none'].includes(table.getAttribute('role')?.toLowerCase()) ||
		table.querySelector('table, img, pre, ul, ol, blockquote, h1, h2, h3, h4, h5, h6, [colspan], [rowspan]')) {
		return null;
	}
	const rows = Array.from(table.querySelectorAll('tr')).filter(row => !hidden(row));
	const cells = rows.map(row => Array.from(row.children)
		.filter(cell => /^(td|th)$/.test(cell.localName) && !hidden(cell)));
	const columns = cells[0]?.length;
	return columns && columns <= 20 && cells.every(row => row.length === columns) &&
		(cells[0].some(cell => cell.localName === 'th') || table.getAttribute('role') === 'table')
		? cells : null;
}

export function richEmailBody(source, {showImages = false} = {}) {
	if (!source || source.length > 256 * 1024) return '';
	const {document} = parseHTML(/<body(?:\s|>)/i.test(source)
		? source : `<html><body>${source}</body></html>`);
	const out = [];
	const images = new Set();
	let pending = '';
	let blocks = 0;
	let size = 0;

	function emit(html, count = 1) {
		out.push(html);
		blocks += count;
		size += html.length;
	}

	function flush() {
		if (pending.trim()) emit(`<p>${pending.trim()}</p>`);
		pending = '';
	}

	function inline(node, depth = 0) {
		if (depth >= 12) return '';
		if (node.nodeType === 3) return escapeTelegramHtml(node.nodeValue.replace(/\s+/g, ' '));
		if (node.nodeType !== 1 || OMIT.has(node.localName) || hidden(node)) return '';
		if (node.localName === 'br') return '<br>';
		if (node.localName === 'img') return '';
		const content = Array.from(node.childNodes, child => inline(child, depth + 1)).join('');
		const href = node.localName === 'a' && safeEmailUrl(node.getAttribute('href'));
		if (href && content.trim()) return `<a href="${escapeTelegramHtml(href)}">${content}</a>`;
		const tag = INLINE.get(node.localName);
		if (tag && content.trim()) return `<${tag}>${content}</${tag}>`;
		return BLOCK.test(node.localName) ? ` ${content} ` : content;
	}

	function visit(node, depth = 0, imageLink = null) {
		if (depth >= 24 || blocks >= MAX_BLOCKS || size + pending.length > MAX_HTML) return;
		if (node.nodeType !== 1) {
			pending += inline(node);
			return;
		}
		const tag = node.localName;
		if (OMIT.has(tag) || hidden(node)) return;
		if (tag === 'br') {
			if (pending.trim()) pending += '<br>';
			return;
		}
		if (tag === 'img') {
			if (tinyImage(node)) return;
			const alt = (node.getAttribute('alt') || '').trim().slice(0, 160);
			if (showImages) {
				const src = safeEmailUrl(node.getAttribute('src'), true) || safeEmailUrl(node.getAttribute('data-src'), true);
				if (src && images.size < MAX_IMAGES && !images.has(src)) {
					flush();
					images.add(src);
					emit(`<img src="${escapeTelegramHtml(src)}"/>`);
					if (imageLink) {
						emit(`<p><a href="${escapeTelegramHtml(imageLink)}">${escapeTelegramHtml(alt || 'Open image link')}</a></p>`);
					}
					return;
				}
			}
			if (alt && !/^(image|photo|banner)$/i.test(alt)) {
				pending += imageLink
					? ` <a href="${escapeTelegramHtml(imageLink)}">${escapeTelegramHtml(alt)}</a> `
					: ` ${escapeTelegramHtml(alt)} `;
			}
			return;
		}
		if (tag === 'table') {
			const rows = dataRows(node);
			if (rows && rows.length < 35) {
				flush();
				const caption = node.querySelector('caption');
				if (caption) emit(`<p>${inline(caption).trim()}</p>`);
				const body = rows.map(row => `<tr>${row.map(cell =>
					`<${cell.localName}>${inline(cell).trim()}</${cell.localName}>`).join('')}</tr>`).join('');
				emit(`<table>${body}</table>`, rows.length + 1);
				return;
			}
		}
		if ((tag === 'a' || INLINE.has(tag)) && !node.querySelector('img')) {
			pending += inline(node);
			return;
		}
		if (/^h[1-6]$/.test(tag) && !node.querySelector('img')) {
			flush();
			const heading = inline(node).trim();
			if (heading) emit(`<${tag}>${heading}</${tag}>`);
			return;
		}
		if (tag === 'pre') {
			flush();
			emit(`<pre>${escapeTelegramHtml(node.textContent.trim())}</pre>`);
			return;
		}
		if (tag === 'hr') {
			flush();
			emit('<hr>');
			return;
		}
		const block = BLOCK.test(tag);
		if (block) flush();
		if (tag === 'li') pending = '• ';
		const link = tag === 'a' ? safeEmailUrl(node.getAttribute('href')) : imageLink;
		for (const child of node.childNodes) visit(child, depth + 1, link);
		if (block) flush();
	}

	for (const child of document.body.childNodes) visit(child);
	flush();
	return blocks < MAX_BLOCKS && size <= MAX_HTML ? out.join('\n') : '';
}
