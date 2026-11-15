import { describe, it, expect, vi, beforeEach } from 'vitest';
import publicService from '../../src/service/public-service';
import roleService from '../../src/service/role-service';
import reqUtils from '../../src/utils/req-utils';
import { t } from '../../src/i18n/i18n';

const DEFAULT_ROLES = [{ roleId: 1, name: 'default', isDefault: 1 }];

function mockDb(impl) {
	const recorded = [];
	const db = {
		recorded,
		prepare: (sql) => {
			const stmt = {
				sql,
				args: undefined,
				bind: (...args) => {
					stmt.args = args;
					return stmt;
				},
			};
			recorded.push(stmt);
			return stmt;
		},
		batch: impl,
	};
	return db;
}

function mockContext({ db, userAgent }) {
	return {
		env: {
			db,
			domain: ['example.com'],
		},
		req: {
			header: (name) => {
				if (name.toLowerCase() === 'user-agent') return userAgent;
				return undefined;
			},
		},
	};
}

const HOSTILE_UA =
	'Mozilla/5.0 (Linux; Android 10; K\',(select 1),\'x) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

describe('public-service addUser SQL parameterization', () => {
	beforeEach(() => {
		vi.restoreAllMocks();
		vi.spyOn(roleService, 'roleSelectUse').mockResolvedValue(DEFAULT_ROLES);
	});

	it('never interpolates UA values into SQL; binds them instead', async () => {
		const db = mockDb(async () => []);
		const c = mockContext({ db, userAgent: HOSTILE_UA });
		const ua = reqUtils.getUserAgent(c);

		await publicService.addUser(c, {
			list: [
				{ email: 'a@example.com', password: 'password123' },
				{ email: 'b@example.com', password: 'password123' },
			],
		});

		expect(db.recorded.length).toBe(5);
		for (const stmt of db.recorded) {
			expect(stmt.sql).not.toContain(`',(select 1),'`);
			expect(stmt.sql).not.toContain('select 1');
			expect(stmt.sql).not.toContain(`'`);
		}
		const userInserts = db.recorded.filter((s) => s.sql.includes('INSERT INTO user'));
		const accountInserts = db.recorded.filter((s) => s.sql.includes('INSERT INTO account'));
		expect(userInserts).toHaveLength(2);
		expect(accountInserts).toHaveLength(2);
		for (const stmt of userInserts) {
			expect(stmt.args).toHaveLength(11);
			for (const value of [ua.os, ua.browser, ua.device].filter(Boolean)) {
				expect(stmt.args).toContain(value);
			}
		}
		for (const stmt of accountInserts) {
			expect(stmt.args).toHaveLength(2);
		}
	});

	it('binds exact hostile getUserAgent strings without touching SQL text', async () => {
		const hostile = { os: `x'),(select 1),('`, browser: '', device: `K',(select 1),'x` };
		vi.spyOn(reqUtils, 'getUserAgent').mockReturnValue({ ...hostile });
		const db = mockDb(async () => []);
		const c = mockContext({ db, userAgent: 'ignored' });

		await publicService.addUser(c, { list: [{ email: 'a@example.com', password: 'password123' }] });

		const userInserts = db.recorded.filter((s) => s.sql.includes('INSERT INTO user'));
		expect(userInserts).toHaveLength(1);
		expect(userInserts[0].args).toContain(hostile.os);
		expect(userInserts[0].args).toContain(hostile.device);
		for (const stmt of db.recorded) {
			expect(stmt.sql).not.toContain('select 1');
		}
	});

	it('maps SQLITE_CONSTRAINT to emailExistDatabase', async () => {
		const db = mockDb(async () => {
			throw new Error('SQLITE_CONSTRAINT: UNIQUE constraint failed: user.email');
		});
		const c = mockContext({ db, userAgent: '' });
		await expect(publicService.addUser(c, { list: [{ email: 'a@example.com', password: 'password123' }] })).rejects.toThrow(
			t('emailExistDatabase')
		);
	});
});
