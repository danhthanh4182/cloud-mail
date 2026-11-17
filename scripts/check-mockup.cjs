// Prototype browser checks. These do not certify native-device behavior.
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require(require.resolve('playwright', {
  paths: [path.resolve(__dirname, '../.harness')],
}));

function expect(condition, message) {
  if (!condition) throw new Error(message);
}

async function main() {
  const browser = await chromium.launch({
    ...(process.env.MOCKUP_BROWSER ? { executablePath: process.env.MOCKUP_BROWSER } : {}),
    headless: true,
    args: ['--no-sandbox'],
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1500, height: 1140 } });
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));
    await page.goto(pathToFileURL(path.resolve(
      __dirname, '../specs/001-native-mail/design/mockup.html',
    )).href);

    const smallTargets = await page.locator('.phone button').evaluateAll(buttons => buttons
      .map(button => ({
        label: button.getAttribute('aria-label') || button.textContent.trim(),
        rect: button.getBoundingClientRect(),
      }))
      .filter(({ rect }) => rect.width > 0 && rect.height > 0
        && (rect.width < 48 || rect.height < 48))
      .map(({ label, rect }) => ({ label, width: rect.width, height: rect.height })));
    expect(smallTargets.length === 0, `Small mobile targets: ${JSON.stringify(smallTargets)}`);

    await page.locator('#search').fill('khong-ton-tai');
    expect((await page.locator('#mail-list').innerText()).includes('Không tìm thấy'), 'Empty results failed');
    await page.locator('#search').fill('Linh');
    expect(await page.locator('#mail-list .mailrow').count() === 1, 'Search filtering failed');
    await page.locator('#mail-list .mailrow').click();
    expect((await page.locator('#phone2 h2').innerText()).includes('Flow Desk'), 'Reader navigation failed');
    await page.locator('#theme').click();
    expect(await page.locator('body').evaluate(element => element.classList.contains('dark')), 'Dark theme failed');
    for (const mode of ['wireframe', 'components', 'mockup']) {
      await page.locator(`[data-mode="${mode}"]`).click();
      expect(await page.locator(`[data-mode="${mode}"]`).evaluate(element => element.classList.contains('active')), `Mode failed: ${mode}`);
    }

    await page.locator('#phone3 .send-btn').click();
    expect(await page.locator('[role="dialog"]').isVisible(), 'Confirmation missing');
    await page.keyboard.press('Shift+Tab');
    expect(await page.locator('#dialog-action').evaluate(element => element === document.activeElement), 'Reverse focus trap failed');
    await page.keyboard.press('Tab');
    expect(await page.locator('#dialog button').first().evaluate(element => element === document.activeElement), 'Forward focus trap failed');
    await page.keyboard.press('Escape');
    expect(await page.locator('#phone3 .send-btn').evaluate(element => element === document.activeElement), 'Focus restoration failed');
    await page.locator('#phone3 .send-btn').click();
    await page.locator('#dialog-action').click();
    expect((await page.locator('#toast').innerText()).includes('Không có email'), 'Simulated send message missing');
    expect(pageErrors.length === 0, `Page errors: ${pageErrors.join('; ')}`);
    console.log('PASS: prototype search/empty/reader/theme/modes/send simulation, 48px mobile targets and dialog focus behavior.');
  } finally {
    await browser.close();
  }
}

main().catch(error => { console.error(error); process.exit(1); });
