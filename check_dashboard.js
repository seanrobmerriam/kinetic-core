const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  
  const consoleMessages = [];
  const consoleErrors = [];
  
  page.on('console', msg => {
    const data = { type: msg.type(), text: msg.text() };
    consoleMessages.push(data);
    if (msg.type() === 'error') {
      consoleErrors.push(msg.text());
    }
  });
  
  try {
    await page.goto('http://localhost:8080', { timeout: 10000 });
    await page.waitForLoadState('networkidle', { timeout: 10000 });
    
    await page.screenshot({ path: '/tmp/dashboard_screenshot.png', fullPage: true });
    
    const domContent = await page.content();
    
    console.log('=== PAGE RENDERING ===');
    console.log('Page title:', await page.title());
    console.log('URL:', page.url);
    
    console.log('\n=== CONSOLE ERRORS ===');
    if (consoleErrors.length > 0) {
      consoleErrors.forEach(err => console.log('ERROR:', err));
    } else {
      console.log('No console errors');
    }
    
    console.log('\n=== CONSOLE MESSAGES (all) ===');
    consoleMessages.forEach(msg => console.log(`[${msg.type}] ${msg.text}`));
    
    console.log('\n=== DOM STRUCTURE (first 3000 chars) ===');
    console.log(domContent.substring(0, 3000));
    
    console.log('\n=== SCREENSHOT SAVED ===');
    console.log('Path: /tmp/dashboard_screenshot.png');
    
  } catch (e) {
    console.log('Error:', e.message);
  }
  
  await browser.close();
})();