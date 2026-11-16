import { describe, it, expect, vi, beforeEach } from 'vitest';
import loginService from '../../src/service/login-service';
import userService from '../../src/service/user-service';
import cryptoUtils from '../../src/utils/crypto-utils';
import JwtUtils from '../../src/utils/jwt-utils';
import { t } from '../../src/i18n/i18n';

function mockContext(kv, ip = '1.2.3.4') {
	return {
		env: {
			jwt_secret: 'test-secret',
			kv: {
				get: async (key, opts) => {
					const value = kv.get(key) ?? null;
					if (value !== null && opts?.type === 'json') {
						return JSON.parse(value);
					}
					return value;
				},
				put: async (key, value) => {
					kv.set(key, value);
				},
				delete: async (key) => {
					kv.delete(key);
				},
			},
		},
		req: {
			header: (name) => {
				if (name === 'CF-Connecting-IP' || name === 'X-Forwarded-For') return ip;
				return null;
			},
		},
	};
}

async function newHash(password) {
	return cryptoUtils.hashPassword(password);
}

describe('login rate limiting', () => {
	beforeEach(() => {
		vi.restoreAllMocks();
		vi.spyOn(JwtUtils, 'generateToken').mockResolvedValue('jwt-token');
		vi.spyOn(userService, 'updateUserInfo').mockResolvedValue(undefined);
	});

	it('returns identical IncorrectPwd for missing users and wrong passwords', async () => {
		const kv = new Map();
		const c = mockContext(kv);
		const stored = await newHash('right-password');
		vi.spyOn(userService, 'selectByEmailIncludeDel').mockImplementation(async (ctx, email) => {
			if (email === 'ghost@example.com') return null;
			return { userId: 3, email, salt: stored.salt, password: stored.hash, isDel: 0, status: 0 };
		});

		const missing = await loginService
			.login(c, { email: 'ghost@example.com', password: 'whatever' })
			.catch((e) => e);
		const wrong = await loginService
			.login(c, { email: 'real@example.com', password: 'wrong' })
			.catch((e) => e);
		expect(missing.message).toBe(t('IncorrectPwd'));
		expect(wrong.message).toBe(t('IncorrectPwd'));
		expect(missing.message).toBe(wrong.message);
	});

	it('runs a dummy hash for missing users', async () => {
		const kv = new Map();
		const c = mockContext(kv);
		vi.spyOn(userService, 'selectByEmailIncludeDel').mockResolvedValue(null);
		const hash = vi.spyOn(cryptoUtils, 'hashPassword');

		await loginService.login(c, { email: 'ghost@example.com', password: 'whatever' }).catch((e) => e);
		expect(hash).toHaveBeenCalledTimes(1);
	});

	it('locks out after 10 failures and never verifies the 11th password', async () => {
		const kv = new Map();
		const c = mockContext(kv);
		const stored = await newHash('right-password');
		vi.spyOn(userService, 'selectByEmailIncludeDel').mockResolvedValue({
			userId: 3,
			email: 'victim@example.com',
			salt: stored.salt,
			password: stored.hash,
			isDel: 0,
			status: 0,
		});
		const verify = vi.spyOn(cryptoUtils, 'verifyPasswordWithStatus');

		for (let i = 0; i < 10; i++) {
			const err = await loginService
				.login(c, { email: 'victim@example.com', password: 'wrong' })
				.catch((e) => e);
			expect(err.message).toBe(t('IncorrectPwd'));
		}
		expect(verify).toHaveBeenCalledTimes(10);

		const locked = await loginService
			.login(c, { email: 'victim@example.com', password: 'right-password' })
			.catch((e) => e);
		expect(locked.message).toBe(t('tooManyLoginAttempts'));
		expect(locked.code).toBe(429);
		expect(verify).toHaveBeenCalledTimes(10);
	});

	it('clears the counter on success', async () => {
		const kv = new Map();
		const c = mockContext(kv);
		const stored = await newHash('right-password');
		vi.spyOn(userService, 'selectByEmailIncludeDel').mockResolvedValue({
			userId: 3,
			email: 'lucky@example.com',
			salt: stored.salt,
			password: stored.hash,
			isDel: 0,
			status: 0,
		});

		const failKey = 'login-fail:' + (await cryptoUtils.sha256Hex('lucky@example.com:1.2.3.4'));
		expect(failKey.startsWith('login-fail:')).toBe(true);

		for (let i = 0; i < 3; i++) {
			await loginService.login(c, { email: 'lucky@example.com', password: 'wrong' }).catch((e) => e);
		}
		expect(kv.get(failKey)).toBe('3');

		await loginService.login(c, { email: 'lucky@example.com', password: 'right-password' });
		expect(kv.has(failKey)).toBe(false);
	});
});
