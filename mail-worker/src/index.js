import app from './hono/webs';
import { email } from './email/email';
import userService from './service/user-service';
import verifyRecordService from './service/verify-record-service';
import emailService from './service/email-service';
import r2Service from './service/r2-service';
import oauthService from './service/oauth-service';
import analysisService from './service/analysis-service';
export default {
	 async fetch(req, env, ctx) {

		const url = new URL(req.url)

		if (url.pathname.startsWith('/api/')) {
			url.pathname = url.pathname.replace('/api', '')
			req = new Request(url.toString(), req)
			return app.fetch(req, env, ctx);
		}

		if (url.pathname.startsWith('/oss/')) {
			const key = url.pathname.slice('/oss/'.length);
			const resp = await r2Service.toObjResp({ env }, key);
			return resp || new Response('Not Found', { status: 404 });
		}

		 if (['/static/','/attachments/'].some(p => url.pathname.startsWith(p))) {
			 const resp = await r2Service.toObjResp({ env }, url.pathname.substring(1));
			 return resp || new Response('Not Found', { status: 404 });
		 }

		return env.assets.fetch(req);
	},
	email,
	async scheduled(c, env, ctx) {
		await runScheduledJobs(env);
	},
};

export const scheduledJobs = [
	['clearRecord', (env) => verifyRecordService.clearRecord({ env })],
	['resetDaySendCount', (env) => userService.resetDaySendCount({ env })],
	['completeReceiveAll', (env) => emailService.completeReceiveAll({ env })],
	['autoClean', (env) => emailService.autoClean({ env })],
	['refreshEchartsCache', (env) => analysisService.refreshEchartsCache({ env })],
	['clearNoBindOathUser', (env) => oauthService.clearNoBindOathUser({ env })],
];

export async function runScheduledJobs(env, jobs = scheduledJobs) {
	for (const [name, run] of jobs) {
		try {
			await run(env);
		} catch (e) {
			console.error(`scheduled job ${name} failed`, e);
		}
	}
}
