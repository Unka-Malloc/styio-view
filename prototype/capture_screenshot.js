const { chromium } = require('playwright-core');
(async () => {
  const executablePath = process.env.VITYO_CHROME_PATH || process.env.CHROME_EXECUTABLE || '/usr/bin/chromium';
  const browser = await chromium.launch({ executablePath });
  const page = await browser.newPage();
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('http://127.0.0.1:4181/vityo-hyper-vis.html');
  await page.waitForTimeout(2000); // 等待 Canvas 动画开始
  await page.screenshot({ path: 'debug_screenshot.png' });
  await browser.close();
  console.log('Screenshot captured to debug_screenshot.png');
})();
