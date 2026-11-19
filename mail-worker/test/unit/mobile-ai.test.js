import {describe,it,expect,vi} from 'vitest';
import aiService from '../../src/service/ai-service';
import {settingConst} from '../../src/const/entity-const';
describe('shared OTP extraction',()=>{
 it('extracts deterministic source code without calling a model',async()=>{const run=vi.fn();expect(await aiService.extractCode({env:{ai:{run}}},{subject:'Verification code',text:'Your code is 482619'},{aiCode:settingConst.aiCode.OPEN})).toBe('482619');expect(run).not.toHaveBeenCalled();});
 it('rejects a model code absent from the email',async()=>{const run=vi.fn().mockResolvedValue({response:'{"code":"999999"}'});expect(await aiService.extractCode({env:{ai:{run}}},{subject:'Account verification',text:'Please verify your account today.'},{aiCode:settingConst.aiCode.OPEN})).toBe('');});
});
