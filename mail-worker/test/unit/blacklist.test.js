import { describe, it, expect } from 'vitest';
import { normalizeBlacklist } from '../../src/service/setting-service';

describe('normalizeBlacklist', () => {
	it('trims, drops empties and joins with single commas', () => {
		expect(normalizeBlacklist(' a, b ,, ')).toBe('a,b');
		expect(normalizeBlacklist('')).toBe('');
		expect(normalizeBlacklist(null)).toBe('');
		expect(normalizeBlacklist(undefined)).toBe('');
	});
});
