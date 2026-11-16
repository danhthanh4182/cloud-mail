import { describe, it, expect, vi, beforeEach } from 'vitest';
import loginService from '../../src/service/login-service';
import userService from '../../src/service/user-service';
import cryptoUtils from '../../src/utils/crypto-utils';
import JwtUtils from '../../src/utils/jwt-utils';
import KvConst from '../../src/const/kv-const';

function mockContext(kv) {
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
		req: { header: () => null },
	};
}

describe('login session profile', () => {
	beforeEach(() => {
		vi.restoreAllMocks();
		vi.spyOn(userService, 'updateUserInfo').mockResolvedValue(undefined);
		vi.spyOn(JwtUtils, 'generateToken').mockResolvedValue('jwt-token');
	});

	it('stores users without password or salt in KV', async () => {
		const kv = new Map();
		const c = mockContext(kv);
		const upgraded = await cryptoUtils.hashPassword('my-password');
		vi.spyOn(userService, 'selectByEmailIncludeDel').mockResolvedValue({
			userId: 7,
			email: 'u@example.com',
			salt: upgraded.salt,
			password: upgraded.hash,
			isDel: 0,
			status: 0,
		});

		await loginService.login(c, { email: 'u@example.com', password: 'my-password' });

		const stored = JSON.parse(kv.get(KvConst.AUTH_INFO + '7'));
		expect(stored.user.email).toBe('u@example.com');
		expect(stored.user.userId).toBe(7);
		expect(stored.user).not.toHaveProperty('password');
		expect(stored.user).not.toHaveProperty('salt');
	});

	it('strips legacy credentials from a pre-existing KV profile', async () => {
		const kv = new Map();
		const c = mockContext(kv);
		const upgraded = await cryptoUtils.hashPassword('my-password');
		const userRow = {
			userId: 7,
			email: 'u@example.com',
			salt: upgraded.salt,
			password: upgraded.hash,
			isDel: 0,
			status: 0,
		};
		vi.spyOn(userService, 'selectByEmailIncludeDel').mockResolvedValue(userRow);
		kv.set(
			KvConst.AUTH_INFO + '7',
			JSON.stringify({
				tokens: ['old-token'],
				user: { ...userRow, password: 'legacy-hash', salt: 'legacy-salt' },
				refreshTime: new Date().toISOString(),
			})
		);

		await loginService.login(c, { email: 'u@example.com', password: 'my-password' });

		const stored = JSON.parse(kv.get(KvConst.AUTH_INFO + '7'));
		expect(stored.user).not.toHaveProperty('password');
		expect(stored.user).not.toHaveProperty('salt');
		expect(stored.tokens).toContain('old-token');
	});
});
