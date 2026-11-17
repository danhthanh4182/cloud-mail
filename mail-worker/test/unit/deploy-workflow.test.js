import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { describe, expect, it } from 'vitest';

// Execute the workflow's shell, substituting only the remote Wrangler command.
const workflow = readFileSync(new URL('../../../.github/workflows/deploy-cloudflare.yml', import.meta.url), 'utf8').replace(/\r\n/g, '\n');
const deployStep = workflow.split('        id: deploy\n')[1].split('\n      - name:')[0];
const deployScript = deployStep.split('        run: |\n')[1]
	.split('\n').map(line => line.slice(10)).join('\n');

function runDeploy(exitCode) {
	return spawnSync('bash', ['-e', '-o', 'pipefail'], {
		encoding: 'utf8',
		timeout: 30000,
		input: `
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"
export GITHUB_OUTPUT="$workdir/output"
pnpm() {
  printf '%s\\n' 'Uploading Worker' 'https://cloud-mail.example.workers.dev'
  return ${exitCode}
}
${deployScript}
cat "$GITHUB_OUTPUT"
`,
	});
}

describe('deployment workflow failure propagation', () => {
	it('fails the job and publishes no URL when Wrangler deployment fails', () => {
		const result = runDeploy(1);
		expect(result.error).toBeUndefined();
		expect(result.status).toBe(1);
		expect(result.stdout).not.toContain('worker_url=');
	}, 45000);

	it('publishes the deployed URL after Wrangler succeeds', () => {
		const result = runDeploy(0);
		expect(result.error).toBeUndefined();
		expect(result.status).toBe(0);
		expect(result.stdout).toContain('worker_url=https://cloud-mail.example.workers.dev');
	}, 45000);
});
