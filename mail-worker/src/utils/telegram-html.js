import { parseHTML } from 'linkedom';
import emailUtils from './email-utils';

const TELEGRAM_TEXT_LIMIT = 3500;
const TRUNCATED_SUFFIX = '...';
const SAFE_HREF = /^(https?|mailto|tg):/i;

function escapeHtml(text = '') {
	return text
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;');
}

function escapeAttr(text = '') {
	return escapeHtml(text).replace(/"/g, '&quot;');
}

function isSafeHref(href) {
	return typeof href === 'string' && SAFE_HREF.test(href.trim());
}

function pushText(out, raw, ctx) {
	if (ctx.done) return;
	const text = raw.replace(/\s+/g, ' ');
	if (!text || (text === ' ' && ctx.atBreak)) return;
	const room = ctx.limit - ctx.used - TRUNCATED_SUFFIX.length;
	if (room <= 0) {
		ctx.done = true;
		ctx.truncated = ctx.used > 0;
		return;
	}
	let shown = text;
	if (shown.length > room) {
		shown = shown.slice(0, room);
		ctx.done = true;
		ctx.truncated = true;
	}
	out.push(ctx.raw ? shown : escapeHtml(shown));
	ctx.used += shown.length;
	ctx.atBreak = false;
}

function breakBefore(out, ctx) {
	if (!ctx.atBreak) {
		out.push('\n\n');
		ctx.atBreak = true;
	}
}

function renderChildren(node, out, ctx) {
	for (const child of node.childNodes || []) {
		if (ctx.done) return;
		renderNode(child, out, ctx);
	}
}

function renderInline(node, out, ctx) {
	renderChildren(node, out, ctx);
}

function inlineText(node, ctx) {
	const out = [];
	const sub = { limit: ctx.limit, used: ctx.used, done: false, truncated: false, atBreak: true, raw: true, omitImages: ctx.omitImages };
	renderChildren(node, out, sub);
	ctx.used = sub.used;
	if (sub.done) {
		ctx.done = true;
		ctx.truncated = ctx.truncated || sub.truncated;
	}
	return out.join('').replace(/\s+/g, ' ').trim();
}

function renderNode(node, out, ctx) {
	if (ctx.done) return;
	if (node.nodeType === 3) {
		pushText(out, node.nodeValue || '', ctx);
		return;
	}
	if (node.nodeType !== 1) return;
	const tag = (node.tagName || '').toLowerCase();
	if (ctx.raw) {
		if (['script', 'style', 'title', 'noscript', 'template', 'head', 'meta', 'link', 'input', 'select', 'textarea'].includes(tag)) return;
		if (tag === 'br') {
			pushText(out, ' ', ctx);
		} else if (tag === 'img') {
			if (ctx.omitImages) return;
			const alt = (node.getAttribute('alt') || '').trim() || 'image';
			if (isSafeHref((node.getAttribute('src') || '').trim()) || node.getAttribute('alt')) pushText(out, `📷 ${alt}`, ctx);
		} else {
			const block = /^(?:p|div|section|article|header|footer|main|aside|figure|figcaption|form|button|h[1-6]|ul|ol|li|table|thead|tbody|tfoot|tr|td|th|blockquote|pre|hr)$/.test(tag);
			if (block) pushText(out, ' ', ctx);
			renderChildren(node, out, ctx);
			if (block) pushText(out, ' ', ctx);
		}
		return;
	}

	switch (tag) {
		case 'script':
		case 'style':
		case 'title':
		case 'noscript':
		case 'template':
		case 'head':
		case 'meta':
		case 'link':
		case 'input':
		case 'select':
		case 'textarea':
			return;
		case 'br':
			out.push('\n');
			ctx.used += 1;
			ctx.atBreak = true;
			if (ctx.used >= ctx.limit - TRUNCATED_SUFFIX.length) ctx.done = true;
			return;
		case 'hr':
			breakBefore(out, ctx);
			out.push('---\n\n');
			ctx.atBreak = true;
			return;
		case 'h1':
		case 'h2':
		case 'h3':
		case 'h4':
		case 'h5':
		case 'h6':
			breakBefore(out, ctx);
			out.push('<b>');
			renderInline(node, out, ctx);
			out.push('</b>\n\n');
			ctx.atBreak = true;
			return;
		case 'p':
		case 'div':
		case 'section':
		case 'article':
		case 'header':
		case 'footer':
		case 'main':
		case 'aside':
		case 'figure':
		case 'figcaption':
		case 'form':
		case 'button': {
			const only = (node.textContent || '').trim();
			if (/^(?=.*\d)[A-Za-z0-9]{4,12}$/.test(only) && !node.querySelector('a, img')) {
				breakBefore(out, ctx);
				out.push('<code>');
				pushText(out, only, ctx);
				out.push('</code>\n\n');
				ctx.atBreak = true;
				return;
			}
			breakBefore(out, ctx);
			renderInline(node, out, ctx);
			out.push('\n\n');
			ctx.atBreak = true;
			return;
		}
		case 'ul':
		case 'ol': {
			let index = 0;
			breakBefore(out, ctx);
			for (const child of node.childNodes || []) {
				if (ctx.done) break;
				if (child.nodeType === 1 && child.tagName.toLowerCase() === 'li') {
					index += 1;
					const marker = tag === 'ol' ? `${index}. ` : '• ';
					pushText(out, marker, ctx);
					renderInline(child, out, ctx);
					out.push('\n');
					ctx.atBreak = true;
				} else {
					renderNode(child, out, ctx);
				}
			}
			out.push('\n');
			ctx.atBreak = true;
			return;
		}
		case 'li':
			pushText(out, '• ', ctx);
			renderInline(node, out, ctx);
			out.push('\n');
			ctx.atBreak = true;
			return;
		case 'tr':
			renderInline(node, out, ctx);
			out.push('\n');
			ctx.atBreak = true;
			return;
		case 'td':
		case 'th':
			renderInline(node, out, ctx);
			pushText(out, ' | ', ctx);
			return;
		case 'table':
		case 'thead':
		case 'tbody':
		case 'tfoot':
			breakBefore(out, ctx);
			renderInline(node, out, ctx);
			out.push('\n');
			ctx.atBreak = true;
			return;
		case 'a': {
			const href = (node.getAttribute('href') || '').trim();
			const label = inlineText(node, ctx);
			if (isSafeHref(href) && (label || !ctx.omitImages || !node.querySelector('img'))) {
				out.push(`<a href="${escapeAttr(href)}">${label ? escapeHtml(label) : escapeHtml(href)}</a>`);
				ctx.atBreak = false;
			} else if (label) {
				pushText(out, label, ctx);
			}
			return;
		}
		case 'img': {
			if (ctx.omitImages) return;
			const src = (node.getAttribute('src') || '').trim();
			const alt = (node.getAttribute('alt') || '').trim() || 'image';
			if (isSafeHref(src)) {
				out.push(`<a href="${escapeAttr(src)}">📷 ${escapeHtml(alt)}</a>`);
				ctx.atBreak = false;
			} else if ((node.getAttribute('alt') || '').trim()) {
				pushText(out, `📷 ${alt}`, ctx);
			}
			return;
		}
		case 'b':
		case 'strong':
			out.push('<b>');
			renderInline(node, out, ctx);
			out.push('</b>');
			return;
		case 'i':
		case 'em':
			out.push('<i>');
			renderInline(node, out, ctx);
			out.push('</i>');
			return;
		case 'u':
		case 'ins':
			out.push('<u>');
			renderInline(node, out, ctx);
			out.push('</u>');
			return;
		case 's':
		case 'strike':
		case 'del':
			out.push('<s>');
			renderInline(node, out, ctx);
			out.push('</s>');
			return;
		case 'code':
			out.push('<code>');
			renderInline(node, out, ctx);
			out.push('</code>');
			return;
		case 'pre': {
			const raw = node.textContent || '';
			const text = raw.replace(/\n{3,}/g, '\n\n');
			if (text.trim()) {
				breakBefore(out, ctx);
				out.push(`<pre>${escapeHtml(text.trim())}</pre>\n\n`);
				ctx.used += text.trim().length;
				if (ctx.used >= ctx.limit - TRUNCATED_SUFFIX.length) {
					ctx.done = true;
					ctx.truncated = true;
				}
			}
			ctx.atBreak = true;
			return;
		}
		case 'blockquote':
			breakBefore(out, ctx);
			out.push('<blockquote>');
			renderInline(node, out, ctx);
			out.push('</blockquote>\n\n');
			ctx.atBreak = true;
			return;
		default:
			renderInline(node, out, ctx);
	}
}

function trimTableSeparators(line) {
	let end = line.length;
	let sawPipe = false;
	while (end > 0 && (line[end - 1] === '|' || line[end - 1] === ' ' || line[end - 1] === '\t')) {
		if (line[end - 1] === '|') sawPipe = true;
		end--;
	}
	return sawPipe ? line.slice(0, end) : line;
}

function cleanup(tgHtml) {
	const pres = [];
	const token = id => `\u0000PRE${id}\u0000`;
	const kept = tgHtml.replace(/<pre>[\s\S]*?<\/pre>/g, match => {
		pres.push(match);
		return token(pres.length - 1);
	});
	const lines = kept
		.split('\n')
		.map(line => trimTableSeparators(line.replace(/[ \t]+/g, ' ')).trim())
		.join('\n')
		.replace(/\n{3,}/g, '\n\n')
		.trim();
	return lines.replace(/\u0000PRE(\d+)\u0000/g, (_, id) => pres[Number(id)] || '');
}

export function htmlToTelegram(html, maxLength = TELEGRAM_TEXT_LIMIT, {omitImages = false} = {}) {
	const limit = Math.max(0, Number(maxLength) || 0);
	if (!html || !limit) return '';
	try {
		const wrapped = html.includes('<body')
			? html
			: `<!DOCTYPE html><html><body>${html}</body></html>`;
		const { document } = parseHTML(wrapped);
		document.querySelectorAll('script, style, title, noscript').forEach(el => el.remove());
		const ctx = { limit, used: 0, done: false, truncated: false, atBreak: true, omitImages };
		const out = [];
		renderChildren(document.body, out, ctx);
		let result = cleanup(out.join(''));
		if (ctx.truncated && result && !result.endsWith(TRUNCATED_SUFFIX)) {
			result += TRUNCATED_SUFFIX;
		}
		return result;
	} catch (e) {
		console.error(e);
		const text = emailUtils.formatText(emailUtils.htmlToText(html));
		if (!text) return '';
		return text.length <= limit ? escapeHtml(text) : `${escapeHtml(text.slice(0, limit - TRUNCATED_SUFFIX.length))}${TRUNCATED_SUFFIX}`;
	}
}

export default { htmlToTelegram };
