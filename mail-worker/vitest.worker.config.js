import { defineWorkersConfig } from '@cloudflare/vitest-pool-workers/config';

export default defineWorkersConfig({
	test: {
		include: ['test/worker/**/*.test.js'],
		poolOptions: {
			workers: {
				wrangler: { configPath: './wrangler.vitest.toml' },
			},
		},
	},
});
