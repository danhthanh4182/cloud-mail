import { describe, it, expect, vi, beforeEach } from 'vitest';
import loginService from '../../src/service/login-service';
import userService from '../../src/service/user-service';
import cryptoUtils from '../../src/utils/crypto-utils';
import JwtUtils from '../../src/utils/jwt-utils';

async function legacyHash(password, salt) {
	const data = new TextEncoder().encode(salt + password);
	const digest = await crypto.subtle.digest('SHA-256', data);
	return btoa(String.fromCharCode(...new Uint8Array(digest)));
}

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
	};
}

describe('login password upgrade', () => {
	beforeEach(() => {
		vi.restoreAllMocks();
	});

	it('rehashes a legacy password on first login, then skips reset', async () => {
		const kv = new Map();
		const c = mockContext(kv);
		const salt = 'upgradesalt';
		const userRow = {
			userId: 7,
			email: 'u@example.com',
			salt,
			password: await legacyHash('my-password', salt),
			isDel: 0,
			status: 0,
		};
		vi.spyOn(userService, 'selectByEmailIncludeDel').mockResolvedValue(userRow);
		vi.spyOn(userService, 'updateUserInfo').mockResolvedValue(undefined);
		const reset = vi.spyOn(userService, 'resetPassword').mockResolvedValue(undefined);
		vi.spyOn(JwtUtils, 'generateToken').mockResolvedValue('jwt-token');

		await loginService.login(c, { email: 'u@example.com', password: 'my-password' });
		expect(reset).toHaveBeenCalledTimes(1);
		expect(reset).toHaveBeenCalledWith(c, { password: 'my-password' }, 7);

		const upgraded = await cryptoUtils.hashPassword('my-password');
		userRow.salt = upgraded.salt;
		userRow.password = upgraded.hash;

		await loginService.login(c, { email: 'u@example.com', password: 'my-password' });
		expect(reset).toHaveBeenCalledTimes(1);
	});
});
