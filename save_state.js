const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: false }); // 눈으로 로그인
  const context = await browser.newContext();
  const page = await context.newPage();

  await page.goto('https://btracker-cns.fii-foxconn.com/vaas/');
  console.log("로그인 완료 후 콘솔로 돌아오면 Enter 치세요.");
  process.stdin.once('data', async () => {
    await context.storageState({ path: 'state.json' });
    await browser.close();
    console.log("✅ state.json 저장 완료");
    process.exit(0);
  });
})();

