import { describe, it, expect } from 'vitest';
import { matchesPathPrefix } from '../../src/security/path-match';

describe('matchesPathPrefix', () => {
	it('matches exact paths and real children only', () => {
		expect(matchesPathPrefix('/test', '/test')).toBe(true);
		expect(matchesPathPrefix('/testfoo', '/test')).toBe(false);
		expect(matchesPathPrefix('/test/foo', '/test')).toBe(true);
		expect(matchesPathPrefix('/oss', '/ossfoo')).toBe(false);
		expect(matchesPathPrefix('/oss/a.png', '/oss')).toBe(true);
		expect(matchesPathPrefix('/setting/websiteConfig', '/setting/websiteConfig')).toBe(true);
		expect(matchesPathPrefix('/setting/websiteConfig/extra', '/setting/websiteConfig')).toBe(true);
		expect(matchesPathPrefix('/setting/websiteConfigX', '/setting/websiteConfig')).toBe(false);
	});
});
