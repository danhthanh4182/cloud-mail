import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import { extractVerificationCode } from '../../src/service/mobile/domain.js';
const fixtures = JSON.parse(fs.readFileSync(new URL('../../../specs/001-native-mail/contracts/fixtures/otp.json', import.meta.url), 'utf8'));
describe('source validated verification codes', () => {
 for (const f of fixtures) it(f.name, () => expect(extractVerificationCode(f.subject, f.body)).toBe(f.expected));
});
