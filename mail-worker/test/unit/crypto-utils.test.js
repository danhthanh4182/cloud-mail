import { describe, it, expect } from 'vitest';
import cryptoUtils from '../../src/utils/crypto-utils';

async function legacyHash(password, salt) {
	const data = new TextEncoder().encode(salt + password);
	const digest = await crypto.subtle.digest('SHA-256', data);
	return btoa(String.fromCharCode(...new Uint8Array(digest)));
}

describe('crypto-utils password hashing', () => {
	it('hashes with pbkdf2-sha256 100000 and verifies', async () => {
		const { salt, hash } = await cryptoUtils.hashPassword('correct horse');
		expect(hash).toMatch(/^pbkdf2-sha256\$100000\$[A-Za-z0-9+/=]+$/);

		const ok = await cryptoUtils.verifyPasswordWithStatus('correct horse', salt, hash);
		expect(ok).toEqual({ valid: true, needsRehash: false });

		const bad = await cryptoUtils.verifyPasswordWithStatus('wrong', salt, hash);
		expect(bad.valid).toBe(false);
	});

	it('accepts legacy sha256 hashes and flags them for rehash', async () => {
		const salt = 'legacysalt';
		const stored = await legacyHash('old-password', salt);
		const status = await cryptoUtils.verifyPasswordWithStatus('old-password', salt, stored);
		expect(status).toEqual({ valid: true, needsRehash: true });

		const wrong = await cryptoUtils.verifyPasswordWithStatus('nope', salt, stored);
		expect(wrong.valid).toBe(false);
	});

	it('rejects malformed new-format hashes without throwing', async () => {
		const status = await cryptoUtils.verifyPasswordWithStatus('x', 's', 'pbkdf2-sha256$broken');
		expect(status).toEqual({ valid: false, needsRehash: false });
	});

	it('generates 16-char alphanumeric passwords', () => {
		for (let i = 0; i < 1000; i++) {
			const pwd = cryptoUtils.genRandomPwd();
			expect(pwd).toHaveLength(16);
			expect(pwd).toMatch(/^[A-Za-z0-9]{16}$/);
		}
	});

	it('compares strings in constant time', () => {
		expect(cryptoUtils.timingSafeEqualString('abc', 'abc')).toBe(true);
		expect(cryptoUtils.timingSafeEqualString('abc', 'abd')).toBe(false);
		expect(cryptoUtils.timingSafeEqualString('abc', 'abcd')).toBe(false);
	});
});
