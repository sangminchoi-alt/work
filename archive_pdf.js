const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

// ===============================
// 설정
// ===============================
const URLS_FILE = path.join(__dirname, 'mantis_issue_list_20260114.txt');
const STATE_FILE = path.join(__dirname, 'state.json');
const OUTPUT_BASE = path.join(__dirname, 'archives');
const PDF_DIR = path.join(OUTPUT_BASE, 'pdf');
const PNG_DIR = path.join(OUTPUT_BASE, 'png');

// ===============================
// 유틸
// ===============================
function loadUrls(filePath) {
  return fs.readFileSync(filePath, 'utf-8')
    .split('\n')
    .map(l => l.trim())
    .filter(l => l && !l.startsWith('#'));
}

function getIdFromUrl(url) {
  try {
    return new URL(url).searchParams.get('id') || 'unknown';
  } catch {
    return 'invalid';
  }
}

function nowTimestamp() {
  const d = new Date();
  const pad = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

// ===============================
// 메인
// ===============================
(async () => {
  // 디렉터리 준비
  fs.mkdirSync(PDF_DIR, { recursive: true });
  fs.mkdirSync(PNG_DIR, { recursive: true });

  const urls = loadUrls(URLS_FILE);
  if (urls.length === 0) {
    console.error('❌ urls.txt 에 URL 이 없습니다.');
    process.exit(1);
  }

  console.log(`📌 총 ${urls.length} 개 URL 처리 시작`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    storageState: STATE_FILE
  });

  for (const url of urls) {
    const id = getIdFromUrl(url);
    const ts = nowTimestamp();
    const baseName = `btracker_${id}_${ts}`;

    const pdfPath = path.join(PDF_DIR, `${baseName}.pdf`);
    const pngPath = path.join(PNG_DIR, `${baseName}.png`);

    const page = await context.newPage();

    try {
      console.log(`➡️  처리중: ${url}`);

      await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
      await page.waitForTimeout(1500);

      // 🔽 lazy loading / 스크롤 대응
      await page.evaluate(async () => {
        await new Promise(resolve => {
          let totalHeight = 0;
          const distance = 500;
          const timer = setInterval(() => {
            window.scrollBy(0, distance);
            totalHeight += distance;
            if (totalHeight >= document.body.scrollHeight) {
              clearInterval(timer);
              resolve();
            }
          }, 200);
        });
      });

      // 📸 풀페이지 스크린샷
      await page.screenshot({
        path: pngPath,
        fullPage: true
      });

      // 📄 PDF 저장
      await page.pdf({
        path: pdfPath,
        format: 'A4',
        printBackground: true,
        margin: {
          top: '12mm',
          bottom: '12mm',
          left: '10mm',
          right: '10mm'
        }
      });

      console.log(`✅ 저장 완료`);
      console.log(`   PNG: ${pngPath}`);
      console.log(`   PDF: ${pdfPath}`);

    } catch (err) {
      console.error(`❌ 실패: ${url}`);
      console.error(err.message);
    } finally {
      await page.close();
    }
  }

  await browser.close();
  console.log('🎉 전체 작업 완료');
})();
