import { describe, it, expect, vi, beforeEach } from 'vitest';
import jwtUtils from '../../src/utils/jwt-utils';
import telegramService from '../../src/service/telegram-service';

vi.mock('../../src/entity/orm', () => ({
	default: () => ({
		select: () => ({
			from: () => ({
				where: () => ({
					get: async () => ({ emailId: 9, text: 'hello' }),
				}),
			}),
		}),
	}),
}));

describe('telegram token audience', () => {
	beforeEach(() => {
		vi.restoreAllMocks();
	});

	it('rejects tokens without the tg-view audience', async () => {
		vi.spyOn(jwtUtils, 'verifyToken').mockResolvedValue({ emailId: 9 });
		const content = await telegramService.getEmailContent({}, { token: 'x' });
		expect(content).toContain('Access denied');
	});

	it('renders content for tokens with the tg-view audience', async () => {
		vi.spyOn(jwtUtils, 'verifyToken').mockResolvedValue({ emailId: 9, aud: 'tg-view' });
		const content = await telegramService.getEmailContent({}, { token: 'x' });
		expect(content).not.toContain('Access denied');
		expect(content).toContain('hello');
	});
});
