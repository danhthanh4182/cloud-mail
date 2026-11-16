import { describe, it, expect, vi, beforeEach } from 'vitest';
import r2Service from '../../src/service/r2-service';
import { parseContentDisposition } from '../../src/utils/object-response';
import attService from '../../src/service/att-service';

vi.mock('../../src/entity/orm', () => ({
	default: () => ({
		insert: () => ({
			values: () => ({
				run: async () => [],
			}),
		}),
	}),
}));

describe('att-service dispositions', () => {
	beforeEach(() => {
		vi.restoreAllMocks();
	});

	it('stores a parseable attachment disposition for hostile filenames', async () => {
		const seen = [];
		vi.spyOn(r2Service, 'putObj').mockImplementation(async (c, key, content, metadata) => {
			seen.push(metadata);
		});
		await attService.addAtt({}, [{ key: 'k1', filename: 'a"b\r\n.png', content: new Uint8Array([1]) }]);

		expect(seen).toHaveLength(1);
		const parsed = parseContentDisposition(seen[0].contentDisposition);
		expect(parsed).not.toBeNull();
		expect(parsed.type).toBe('attachment');
		expect(seen[0].contentDisposition).toContain(`filename*=UTF-8''`);
		expect(seen[0].contentDisposition).not.toMatch(/[\r\n]/);
		expect(seen[0].cacheControl).toBeUndefined();
	});

	it('uses inline only for contentId attachments', async () => {
		const seen = [];
		vi.spyOn(r2Service, 'putObj').mockImplementation(async (c, key, content, metadata) => {
			seen.push(metadata);
		});
		await attService.addAtt({}, [
			{ key: 'k2', filename: 'x.png', content: new Uint8Array([1]), contentId: '<x>' },
		]);

		expect(seen).toHaveLength(1);
		const parsed = parseContentDisposition(seen[0].contentDisposition);
		expect(parsed).not.toBeNull();
		expect(parsed.type).toBe('inline');
		expect(seen[0].cacheControl).toBe('max-age=259200');
	});
});
