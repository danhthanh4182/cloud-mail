import { afterEach, describe, expect, it, vi } from 'vitest';
import { parseHTML } from 'linkedom';
import { formatSenderTooltip } from '../../../mail-vue/src/views/analysis/sender-tooltip.js';

function renderLikeECharts(params) {
	const { document } = parseHTML('<html><body></body></html>');
	vi.stubGlobal('document', document);
	const container = document.createElement('div');
	const result = formatSenderTooltip(params);
	if (typeof result === 'string') container.innerHTML = result;
	else container.appendChild(result);
	return container;
}

afterEach(() => vi.unstubAllGlobals());

describe('sender chart tooltip', () => {
	it('displays markup-looking sender names as text rather than executable HTML', () => {
		const name = '<img src=x onerror="globalThis.compromised=1">';
		const tooltip = renderLikeECharts({ name, value: 5, percent: 25, color: '#13DEB9', marker: '<span></span>' });
		expect(tooltip.querySelector('img')).toBeNull();
		expect(tooltip.textContent).toContain(name);
		expect(tooltip.textContent).toContain('5 (25%)');
	});

	it('keeps the chart marker and literal characters in normal sender names', () => {
		const tooltip = renderLikeECharts({ name: 'A & B <team>', value: 12, percent: 40, color: '#13DEB9', marker: '<span></span>' });
		const marker = tooltip.querySelector('span > span');
		expect(marker).not.toBeNull();
		expect(marker.style.backgroundColor.toLowerCase()).toBe('#13deb9');
		expect(tooltip.textContent).toContain('A & B <team>');
		expect(tooltip.textContent).toContain('12 (40%)');
	});
});
