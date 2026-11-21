import {parseHTML} from 'linkedom';
import domainUtils from '../utils/domain-uitls';
import {escapeTelegramHtml, safeEmailUrl} from '../utils/telegram-rich-email';

export default function emailHtmlTemplate(source, domain) {
	const {document} = parseHTML(/<body(?:\s|>)/i.test(source)
		? source : `<html><body>${source}</body></html>`);
	const storageOrigin = domainUtils.toOssDomain(domain);
	for (const node of document.querySelectorAll(
		'script, iframe, frame, object, embed, base, meta, link, form, input, button, svg, math',
	)) node.remove();

	for (const node of document.querySelectorAll('*')) {
		for (const attr of Array.from(node.attributes)) {
			if (/^on/i.test(attr.name) || ['ping', 'srcdoc', 'download'].includes(attr.name)) {
				node.removeAttribute(attr.name);
			}
		}
	}
	for (const link of document.querySelectorAll('a[href]')) {
		const href = safeEmailUrl(link.getAttribute('href'));
		if (!href) {
			link.removeAttribute('href');
			continue;
		}
		link.setAttribute('href', href);
		link.setAttribute('target', '_blank');
		link.setAttribute('rel', 'noopener noreferrer');
	}
	for (const image of document.querySelectorAll('img')) {
		let src = image.getAttribute('src');
		if (src?.startsWith('{{domain}}')) {
			src = storageOrigin && `${storageOrigin}/${src.slice('{{domain}}'.length)}`;
		}
		const embeddedRaster = /^data:image\/(?:png|jpeg|webp|gif|avif);base64,[a-z0-9+/=]+$/i;
		const url = safeEmailUrl(src, true) || safeEmailUrl(image.getAttribute('data-src'), true) ||
			(src?.length <= 2 * 1024 * 1024 && embeddedRaster.test(src) ? src : null);
		if (url) image.setAttribute('src', url);
		else image.removeAttribute('src');
	}

	const styles = Array.from(document.querySelectorAll('head style')).map(node => node.outerHTML).join('');
	const body = document.body;
	const htmlAttrs = ['lang', 'dir', 'class'].map(name => {
		const value = document.documentElement.getAttribute(name);
		return value ? ` ${name}="${escapeTelegramHtml(value)}"` : '';
	}).join('');
	const bodyAttrs = Array.from(body.attributes, ({name, value}) =>
		` ${name}="${escapeTelegramHtml(value)}"`).join('');
	const frame = `<!doctype html><html${htmlAttrs}><head>
	<meta charset="UTF-8">
	<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
	<meta name="referrer" content="no-referrer">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<style>body{margin:0;font:16px/1.5 sans-serif}table,img{max-width:100%}img{height:auto}</style>
	${styles}</head><body${bodyAttrs}>${body.innerHTML}</body></html>`;

	return `<!doctype html><html lang="en"><head><meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<meta name="referrer" content="no-referrer">
	<title>Original email</title>
	<style>html,body{margin:0;height:100%;background:white}iframe{display:block;width:100%;height:100%;border:0}</style>
	</head><body><iframe title="Original email"
	sandbox="allow-popups allow-popups-to-escape-sandbox" referrerpolicy="no-referrer"
	srcdoc="${escapeTelegramHtml(frame)}"></iframe></body></html>`;
}
