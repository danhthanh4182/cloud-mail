import { describe, it, expect, vi, beforeEach } from 'vitest';
import { runScheduledJobs, scheduledJobs } from '../../src/index';

describe('scheduled jobs', () => {
	beforeEach(() => {
		vi.restoreAllMocks();
	});

	it('runs every job even when one fails', async () => {
		const err = vi.spyOn(console, 'error').mockImplementation(() => {});
		const order = [];
		const jobs = [
			['a', () => { throw new Error('x'); }],
			['b', async () => { order.push('b'); }],
			['c', async () => { order.push('c'); }],
		];

		await runScheduledJobs({}, jobs);

		expect(order).toEqual(['b', 'c']);
		expect(err).toHaveBeenCalledTimes(1);
		expect(err.mock.calls[0][0]).toContain('a');
	});

	it('exports the expected job table', () => {
		expect(scheduledJobs.map(([name]) => name)).toEqual([
			'clearRecord',
			'resetDaySendCount',
			'completeReceiveAll',
			'autoClean',
			'refreshEchartsCache',
			'clearNoBindOathUser',
		]);
	});
});
