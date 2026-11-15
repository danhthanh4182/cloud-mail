import { describe, it, expect } from 'vitest';
import emailMsgTemplate from '../../src/template/email-msg';

describe('email-msg escaping', () => {
	it('escapes ampersands before angle brackets', () => {
		const out = emailMsgTemplate({ subject: 'a & b <c>', text: '', content: '' }, 'hide', 'hide', 'hide');
		expect(out).toContain('a &amp; b &lt;c&gt;');
	});
});
