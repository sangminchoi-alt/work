#!/usr/bin/env python3
"""skbtv meminfo 로그로 메모리 추이 그래프(HTML) 생성.

입력 폴더 구조 (download 결과 그대로):
    <ROOT>/<시료번호>/skbtv_meminfo_YYYYMMDD_HHMMSS.log

사용법:
    python3 skbtv_memory_report.py <ROOT> [-o out.html]
        [--start "2026-11-13 10:00"] [--end "2026-11-16 10:00"]
        [--samples samples.txt] [--label "Daily aging · AI5"]

- 시료 순서/색: --samples 파일(한 줄에 시료번호 하나) 순서를 따르고,
  없으면 <ROOT>/samples.txt, 그것도 없으면 폴더 이름순.
- 시간 범위: 파일명 시각 기준(KST). 생략하면 로그 전체 범위.
- 그래프: TOTAL PSS(App Summary), Native Heap / Dalvik Heap 의 Heap Size 열 (MB).
- dumpsys 타임아웃 등으로 값이 없는 로그는 건너뛰고 '누락'으로 집계.
- Python 3 표준 라이브러리만 사용. 결과 HTML 은 Chart.js 를 CDN 에서 불러오므로
  열 때 인터넷 연결이 필요합니다.
"""
import argparse
import datetime as dt
import json
import os
import re
import sys

TS_RE = re.compile(r'(\d{8})_(\d{6})')
PSS_RE = re.compile(r'TOTAL PSS:\s+(\d+)')
NH_RE = re.compile(r'^\s*Native Heap\s+((?:\d+\s+){5}\d+)', re.M)
DH_RE = re.compile(r'^\s*Dalvik Heap\s+((?:\d+\s+){5}\d+)', re.M)
PID_RE = re.compile(r'MEMINFO in pid (\d+)')


def parse_time(s):
    for fmt in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M', '%Y-%m-%d', '%Y%m%d_%H%M%S'):
        try:
            return dt.datetime.strptime(s, fmt)
        except ValueError:
            pass
    sys.exit(f'시간 형식을 알 수 없습니다: {s} (예: "2026-11-13 10:00")')


def file_time(name):
    m = TS_RE.search(name)
    return dt.datetime.strptime(m.group(1) + m.group(2), '%Y%m%d%H%M%S') if m else None


def sample_order(root, samples_file):
    path = samples_file or os.path.join(root, 'samples.txt')
    dirs = sorted(d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d)))
    if os.path.isfile(path):
        names = [l.strip() for l in open(path, encoding='utf-8') if l.strip() and not l.startswith('#')]
        missing = [n for n in names if n not in dirs]
        if missing:
            print('경고: 폴더가 없는 시료는 건너뜀:', ', '.join(missing), file=sys.stderr)
        return [n for n in names if n in dirs]
    elif samples_file:
        sys.exit(f'시료 목록 파일이 없습니다: {samples_file}')
    return dirs


def collect(root, order, start, end):
    files = {}
    for s in order:
        lst = []
        for dirpath, _, names in os.walk(os.path.join(root, s)):
            for n in names:
                if n.startswith('skbtv_') and n.endswith('.log'):
                    t = file_time(n)
                    if t and (start is None or t >= start) and (end is None or t <= end):
                        lst.append((t, os.path.join(dirpath, n)))
        files[s] = sorted(lst)
    return files


def parse_file(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        txt = f.read()
    pss, nh, dh = PSS_RE.search(txt), NH_RE.search(txt), DH_RE.search(txt)
    if not (pss and nh and dh):
        return None
    pid = PID_RE.search(txt)
    return (int(pss.group(1)), int(nh.group(1).split()[5]), int(dh.group(1).split()[5]),
            int(pid.group(1)) if pid else None)


def main():
    ap = argparse.ArgumentParser(description='skbtv meminfo 로그 → 메모리 추이 HTML')
    ap.add_argument('root', help='시료별 폴더가 들어 있는 폴더 (예: work/skbtv)')
    ap.add_argument('-o', '--output', default='skbtv_memory_trend.html', help='출력 HTML 경로')
    ap.add_argument('--start', help='시작 시각 (KST, 예: "2026-11-13 10:00")')
    ap.add_argument('--end', help='종료 시각 (KST, 예: "2026-11-16 10:00")')
    ap.add_argument('--samples', help='시료 순서 파일 (한 줄에 하나)')
    ap.add_argument('--label', default='Daily aging · AI5', help='제목 아래 표시할 설명')
    a = ap.parse_args()

    if not os.path.isdir(a.root):
        sys.exit(f'폴더가 없습니다: {a.root}')
    start = parse_time(a.start) if a.start else None
    end = parse_time(a.end) if a.end else None
    order = sample_order(a.root, a.samples)
    files = collect(a.root, order, start, end)
    order = [s for s in order if files[s]]
    if not order:
        sys.exit('범위 안에 skbtv_*.log 파일이 없습니다.')

    times = [t for s in order for t, _ in files[s]]
    t_start = start or min(times)
    t_end = end or max(times)
    span = int((t_end - t_start).total_seconds())
    hours = span / 3600
    step = 3600 * (1 if hours <= 12 else 3 if hours <= 36 else 6 if hours <= 96 else 12 if hours <= 192 else 24)

    data, miss = {}, {}
    for s in order:
        rows = []
        for t, p in files[s]:
            v = parse_file(p)
            if v:
                rows.append([int((t - t_start).total_seconds()), *v])
        data[s] = rows
        miss[s] = len(files[s]) - len(rows)
        print(f'{s}: 로그 {len(files[s])}개, 사용 {len(rows)}개, 누락 {miss[s]}개')
    order = [s for s in order if data[s]]

    t0 = int(dt.datetime(t_start.year, t_start.month, t_start.day, t_start.hour, t_start.minute,
                         t_start.second, tzinfo=dt.timezone.utc).timestamp() * 1000)
    payload = {'order': order, 's': data, 'miss': miss, 't0': t0, 'span': span, 'step': step}
    rng = f"{t_start:%Y-%m-%d %H:%M} ~ {t_end:%Y-%m-%d %H:%M} (KST)"
    html = (TEMPLATE.replace('__LABEL__', a.label).replace('__N__', str(len(order)))
            .replace('__RANGE__', rng).replace('__DATA__', json.dumps(payload, separators=(',', ':'))))
    os.makedirs(os.path.dirname(os.path.abspath(a.output)), exist_ok=True)
    with open(a.output, 'w', encoding='utf-8') as f:
        f.write('<!doctype html>\n<html lang="ko"><head><meta charset="utf-8">'
                '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">'
                '<style>body{margin:0}[hidden]{display:none!important}</style>\n'
                + html + '\n</html>\n')
    print(f'생성: {a.output} ({rng}, 시료 {len(order)}개)')


TEMPLATE = r'''<title>com.skb.tv 메모리 추이</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+KR:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
/* Layout: one column of three stacked full-width time-series panels, shared legend bar on top, summary table below */
:root {
  --bg: #f7f7f5; --surface: #ffffff; --fg: #1d1d1b; --fg-2: #55554f; --muted: #8a8a82;
  --line: #e4e3de; --grid: #eeede9; --accent: #2a78d6;
  --c1: #2a78d6; --c2: #eb6834; --c3: #1baf7a; --c4: #eda100; --c5: #e87ba4; --c6: #6250d6;
  --font-ui: "IBM Plex Sans KR", "Apple SD Gothic Neo", "Malgun Gothic", system-ui, sans-serif;
  --font-data: "IBM Plex Mono", ui-monospace, Menlo, monospace;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg: #121211; --surface: #1a1a19; --fg: #f0efec; --fg-2: #c3c2b7; --muted: #8d8c84;
  --line: #2e2e2b; --grid: #262624; --accent: #3987e5;
  --c1: #3987e5; --c2: #d95926; --c3: #199e70; --c4: #c98500; --c5: #d55181; --c6: #9085e9;
  color-scheme: dark; } }
:root[data-theme="dark"] {
  --bg: #121211; --surface: #1a1a19; --fg: #f0efec; --fg-2: #c3c2b7; --muted: #8d8c84;
  --line: #2e2e2b; --grid: #262624; --accent: #3987e5;
  --c1: #3987e5; --c2: #d95926; --c3: #199e70; --c4: #c98500; --c5: #d55181; --c6: #9085e9;
  color-scheme: dark; }
* { box-sizing: border-box; }
body { background: var(--bg); color: var(--fg); font-family: var(--font-ui); font-size: 14px; line-height: 1.5; }
.wrap { max-width: 1280px; margin: 0 auto; padding-block: 28px 48px;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px));
  display: flex; flex-direction: column; gap: 20px; }
header h1 { font-size: 22px; font-weight: 600; margin: 0; text-wrap: balance; }
header p { margin: 4px 0 0; color: var(--fg-2); }
.meta { font-family: var(--font-data); font-size: 12px; color: var(--muted); }
.legend { display: flex; flex-wrap: wrap; gap: 6px 8px; align-items: center; }
.legend .grp { font-size: 11px; letter-spacing: .06em; text-transform: uppercase; color: var(--muted); margin-right: 2px; }
.legend .break { flex-basis: 100%; height: 0; }
.chip { display: inline-flex; align-items: center; gap: 6px; padding: 4px 10px; border: 1px solid var(--line); border-radius: 999px;
  background: var(--surface); color: var(--fg); font-family: var(--font-data); font-size: 12px; cursor: pointer; }
.chip:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.chip.off { opacity: .4; }
.chip svg { flex: none; }
.tools { display: flex; gap: 8px; flex-wrap: wrap; }
.btn { font: inherit; font-size: 12px; padding: 4px 10px; border-radius: 6px; border: 1px solid var(--line); background: transparent; color: var(--fg-2); cursor: pointer; }
.btn:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.panel { background: var(--surface); border: 1px solid var(--line); border-radius: 8px; padding: 14px 14px 8px; min-width: 0; }
.panel h2 { font-size: 15px; font-weight: 600; margin: 0; }
.panel .sub { color: var(--muted); font-size: 12px; margin: 2px 0 8px; }
.cv { position: relative; height: 340px; }
.cv canvas { position: absolute; inset: 0; }
.tip { position: fixed; pointer-events: none; z-index: 20; background: var(--surface); color: var(--fg); border: 1px solid var(--line);
  border-radius: 6px; padding: 8px 10px; font-family: var(--font-data); font-size: 12px; box-shadow: 0 6px 20px rgba(0,0,0,.18); min-width: 220px; }
.tip .t { color: var(--fg-2); margin-bottom: 4px; }
.tip .r { display: flex; align-items: center; gap: 6px; justify-content: space-between; }
.tip .r span:first-child { display: inline-flex; align-items: center; gap: 6px; }
.tip .r b { font-weight: 500; font-variant-numeric: tabular-nums; }
.tblwrap { overflow-x: auto; background: var(--surface); border: 1px solid var(--line); border-radius: 8px; }
table { border-collapse: collapse; width: 100%; font-variant-numeric: tabular-nums; font-size: 12.5px; }
th, td { padding: 7px 10px; text-align: right; white-space: nowrap; border-bottom: 1px solid var(--grid); }
th { font-weight: 500; color: var(--fg-2); background: var(--surface); }
thead tr:first-child th { border-bottom: none; padding-bottom: 0; text-align: center; color: var(--muted); font-size: 11px; letter-spacing: .04em; }
td:first-child, th:first-child { text-align: left; font-family: var(--font-data); }
td.up { color: var(--fg); font-weight: 500; }
.note { color: var(--muted); font-size: 12px; margin: 0; }
.view { display: flex; flex-direction: column; gap: 20px; }
.seg { display: inline-flex; align-self: flex-start; border: 1px solid var(--line); border-radius: 8px; padding: 3px; background: var(--surface); gap: 2px; }
.segb { font: inherit; font-size: 13px; padding: 5px 14px; border: 0; border-radius: 6px; background: transparent; color: var(--fg-2); cursor: pointer; }
.segb[aria-selected="true"] { background: var(--fg); color: var(--bg); }
.segb:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.chip.static { cursor: default; font-family: var(--font-ui); }
.grid { display: grid; grid-template-columns: minmax(0, 1fr); gap: 14px; }
.grid .panel h2 { font-family: var(--font-data); font-size: 14px; display: flex; justify-content: space-between; gap: 8px; flex-wrap: wrap; }
.grid .panel h2 .rs { font-family: var(--font-ui); font-weight: 400; font-size: 12px; color: var(--muted); }
.grid .cv { height: 300px; }
@media (max-width: 600px) { .cv { height: 260px; } }
</style>

<div class="wrap">
  <header>
    <h1>com.skb.tv 메모리 사용량 추이</h1>
    <p>__LABEL__ · __N__개 시료 · <span class="meta">__RANGE__, dumpsys meminfo</span></p>
  </header>

  <div class="seg" role="tablist" aria-label="보기 방식">
    <button type="button" class="segb" id="tab-sample" data-v="sample" role="tab">시료별</button>
    <button type="button" class="segb" id="tab-metric" data-v="metric" role="tab">지표별</button>
  </div>

  <div id="viewSample" class="view">
    <div class="legend">
      <span class="chip static">${SW0}TOTAL PSS</span>
      <span class="chip static">${SW1}Native Heap Size</span>
      <span class="chip static">${SW2}Dalvik Heap Size</span>
      <span class="note" style="align-self:center">모든 시료 같은 세로축(MB) · 그래프에 마우스를 올리면 해당 시각 값 표시</span>
    </div>
    <div class="grid" id="grid"></div>
  </div>

  <div id="viewMetric" class="view">
  <div>
    <div class="legend" id="legend"></div>
  </div>
  <div class="tools">
    <button class="btn" id="all" type="button">전체 표시</button>
    <button class="btn" id="none" type="button">전체 숨김</button>
    <span class="note" style="align-self:center">칩 클릭: 표시/숨김 · 칩에 마우스: 강조 · 같은 색은 실선/점선으로 구분</span>
  </div>

  <section class="panel"><h2>TOTAL PSS</h2><p class="sub">App Summary의 TOTAL PSS · MB</p><div class="cv"><canvas id="c0"></canvas></div></section>
  <section class="panel"><h2>Native Heap · Heap Size</h2><p class="sub">MEMINFO 표 Native Heap 행의 Heap Size 열 · MB</p><div class="cv"><canvas id="c1"></canvas></div></section>
  <section class="panel"><h2>Dalvik Heap · Heap Size</h2><p class="sub">MEMINFO 표 Dalvik Heap 행의 Heap Size 열 · MB</p><div class="cv"><canvas id="c2"></canvas></div></section>
  </div>

  <section style="display:flex;flex-direction:column;gap:8px">
    <h2 style="font-size:15px;margin:0">시료별 요약 (MB)</h2>
    <p class="note">시작·종료는 각각 첫·마지막 1시간 평균입니다. 재시작은 pid가 바뀐 횟수, 누락은 dumpsys 타임아웃 등으로 값이 없는 로그 수입니다.</p>
    <div class="tblwrap"><table id="tbl"></table></div>
  </section>
</div>
<div class="tip" id="tip" hidden></div>

<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.min.js"></script>
<script>
const D = __DATA__;
const T0 = D.t0;    // log wall clock (KST) stored as UTC ms
const SPAN = D.span;
const STEP = D.step;
const METRICS = [{i:1,name:'TOTAL PSS'},{i:2,name:'Native Heap Size'},{i:3,name:'Dalvik Heap Size'}];
const ORDER = D.order;
const colorVar = idx => '--c' + ((idx % 6) + 1);
const dashed = s => Math.floor(ORDER.indexOf(s) / 6) % 2 === 1;
const prefix = s => (s.match(/^[A-Za-z]+/) || [''])[0];
const state = { on: Object.fromEntries(ORDER.map(s => [s, true])), hi: null };
const css = n => getComputedStyle(document.documentElement).getPropertyValue(n).trim();
const fmtT = sec => { const d = new Date(T0 + sec*1000); const p = n => String(n).padStart(2,'0');
  return `${p(d.getUTCMonth()+1)}/${p(d.getUTCDate())} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}`; };
const mb = kb => kb/1024;

function swatch(idx, s) {
  const c = `var(${colorVar(idx)})`;
  return `<svg width="22" height="8" aria-hidden="true"><line x1="1" y1="4" x2="21" y2="4" stroke="${c}" stroke-width="2.5" stroke-linecap="round" ${dashed(s)?'stroke-dasharray="5 3"':''}/></svg>`;
}

// legend
const lg = document.getElementById('legend');
let html = '';
ORDER.forEach((s, i) => {
  if (i === 0 || prefix(s) !== prefix(ORDER[i-1])) html += (i ? '<span class="break"></span>' : '') + `<span class="grp">${prefix(s)}</span>`;
  html += `<button type="button" class="chip" data-s="${s}" id="chip-${s}" aria-pressed="true">${swatch(i,s)}${s}</button>`;
});
lg.innerHTML = html;

const charts = METRICS.map((m, k) => {
  const datasets = ORDER.map((s, i) => ({
    label: s,
    data: D.s[s].map(r => ({x: r[0], y: mb(r[m.i])})),
    borderWidth: 1.5, pointRadius: 0, tension: 0, spanGaps: true,
    borderDash: dashed(s) ? [5,3] : [],
  }));
  return new Chart(document.getElementById('c'+k), {
    type: 'line', data: { datasets },
    options: {
      parsing: false, normalized: true, animation: false, responsive: true, maintainAspectRatio: false,
      events: [], plugins: { legend: { display: false }, tooltip: { enabled: false } },
      scales: {
        x: { type: 'linear', min: 0, max: SPAN, ticks: { stepSize: STEP, callback: v => fmtT(v), maxRotation: 0, autoSkip: true } },
        y: { ticks: { callback: v => v + ' MB' } },
      },
    },
    plugins: [{ id: 'cross', afterDatasetsDraw(c) { if (c.$cx == null) return; const {ctx, chartArea:a} = c;
      ctx.save(); ctx.strokeStyle = css('--muted'); ctx.lineWidth = 1; ctx.setLineDash([3,3]);
      ctx.beginPath(); ctx.moveTo(c.$cx, a.top); ctx.lineTo(c.$cx, a.bottom); ctx.stroke(); ctx.restore(); } }],
  });
});

// per-sample small multiples: 3 metrics per sample, shared y scale
const M_COL = ['--c1', '--c2', '--c3'];
const mSw = k => `<svg width="22" height="8" aria-hidden="true"><line x1="1" y1="4" x2="21" y2="4" stroke="var(${M_COL[k]})" stroke-width="2.5" stroke-linecap="round"/></svg>`;
document.querySelectorAll('.chip.static').forEach((el, k) => el.innerHTML = el.innerHTML.replace('${SW' + k + '}', mSw(k)));
const YMAX = Math.ceil(Math.max(...ORDER.flatMap(s => D.s[s].map(r => r[1]))) / 1024 / 100) * 100;
const restarts = s => { const r = D.s[s]; let n = 0; for (let j = 1; j < r.length; j++) if (r[j][4] !== r[j-1][4]) n++; return n; };
const restartAt = s => { const r = D.s[s], out = []; for (let j = 1; j < r.length; j++) if (r[j][4] !== r[j-1][4]) out.push(r[j][0]); return out; };
const grid = document.getElementById('grid');
grid.innerHTML = ORDER.map((s, i) => { const n = restarts(s);
  return `<section class="panel"><h2>${s}<span class="rs">${n ? '앱 재시작 ' + n + '회 (세로 점선)' : '재시작 없음'}</span></h2><div class="cv"><canvas id="s${i}"></canvas></div></section>`; }).join('');
const sCharts = ORDER.map((s, i) => new Chart(document.getElementById('s' + i), {
  type: 'line',
  data: { datasets: METRICS.map(m => ({ label: m.name, data: D.s[s].map(r => ({x: r[0], y: mb(r[m.i])})),
    borderWidth: 1.5, pointRadius: 0, tension: 0, spanGaps: true })) },
  options: {
    parsing: false, normalized: true, animation: false, responsive: true, maintainAspectRatio: false,
    events: [], plugins: { legend: { display: false }, tooltip: { enabled: false } },
    scales: {
      x: { type: 'linear', min: 0, max: SPAN, ticks: { stepSize: STEP, callback: v => fmtT(v), maxRotation: 0, autoSkip: true } },
      y: { min: 0, max: YMAX, ticks: { stepSize: 200, callback: v => v } },
    },
  },
  plugins: [{ id: 'marks', afterDatasetsDraw(c) { const {ctx, chartArea: a} = c;
    ctx.save(); ctx.setLineDash([3,3]); ctx.lineWidth = 1;
    ctx.strokeStyle = css('--fg-2'); ctx.globalAlpha = .45;
    restartAt(s).forEach(x => { const px = c.scales.x.getPixelForValue(x); ctx.beginPath(); ctx.moveTo(px, a.top); ctx.lineTo(px, a.bottom); ctx.stroke(); });
    ctx.globalAlpha = 1;
    if (c.$cx != null) { ctx.strokeStyle = css('--muted'); ctx.beginPath(); ctx.moveTo(c.$cx, a.top); ctx.lineTo(c.$cx, a.bottom); ctx.stroke(); }
    ctx.restore(); } }],
}));
sCharts.forEach((c, i) => {
  const s = ORDER[i], cv = c.canvas;
  const hide = () => { tip.hidden = true; c.$cx = null; c.draw(); };
  const move = ev => {
    const r = cv.getBoundingClientRect(), px = ev.clientX - r.left, a = c.chartArea;
    if (px < a.left || px > a.right) { hide(); return; }
    const x = c.scales.x.getValueForPixel(px); c.$cx = px; c.draw();
    const row = nearest(D.s[s], x);
    tip.innerHTML = `<div class="t">${s} · ${fmtT(x)}</div>` + (row ? METRICS.map((m, k) =>
      `<div class="r"><span>${mSw(k)}${m.name}</span><b>${mb(row[m.i]).toFixed(1)} MB</b></div>`).join('') : '<div class="t">이 시점 값 없음</div>');
    placeTip(ev);
  };
  cv.addEventListener('mousemove', move); cv.addEventListener('mouseleave', hide);
  cv.addEventListener('touchstart', e => move(e.touches[0]), {passive: true});
  cv.addEventListener('touchmove', e => move(e.touches[0]), {passive: true});
  cv.addEventListener('touchend', hide);
});

// view switch
function setView(v) {
  document.getElementById('viewSample').hidden = v !== 'sample';
  document.getElementById('viewMetric').hidden = v !== 'metric';
  document.querySelectorAll('.segb').forEach(b => b.setAttribute('aria-selected', b.dataset.v === v));
  (v === 'sample' ? sCharts : charts).forEach(c => c.resize());
  try { localStorage.setItem('skbtv-view', v); } catch (e) {}
}
document.querySelectorAll('.segb').forEach(b => b.onclick = () => setView(b.dataset.v));

function applyStyle() {
  Chart.defaults.font.family = css('--font-data');
  sCharts.forEach(c => {
    ['x', 'y'].forEach(ax => { c.options.scales[ax].grid = { color: css('--grid') }; c.options.scales[ax].ticks.color = css('--muted'); c.options.scales[ax].border = { color: css('--line') }; });
    c.data.datasets.forEach((ds, k) => ds.borderColor = css(M_COL[k]));
    c.update('none');
  });
  charts.forEach(c => {
    c.options.scales.x.grid = { color: css('--grid') }; c.options.scales.y.grid = { color: css('--grid') };
    c.options.scales.x.ticks.color = css('--muted'); c.options.scales.y.ticks.color = css('--muted');
    c.options.scales.x.border = { color: css('--line') }; c.options.scales.y.border = { color: css('--line') };
    c.data.datasets.forEach((ds, i) => {
      const s = ORDER[i], col = css(colorVar(i));
      const dim = state.hi && state.hi !== s;
      ds.borderColor = dim ? col + '33' : col;
      ds.borderWidth = state.hi === s ? 2.5 : 1.5;
      ds.hidden = !state.on[s];
      ds.order = state.hi === s ? 0 : 1;
    });
    c.update('none');
  });
  document.querySelectorAll('.chip').forEach(b => { const on = state.on[b.dataset.s]; b.classList.toggle('off', !on); b.setAttribute('aria-pressed', on); });
}

lg.addEventListener('click', e => { const b = e.target.closest('.chip'); if (!b) return; state.on[b.dataset.s] = !state.on[b.dataset.s]; applyStyle(); });
lg.addEventListener('mouseover', e => { const b = e.target.closest('.chip'); if (b && state.on[b.dataset.s]) { state.hi = b.dataset.s; applyStyle(); } });
lg.addEventListener('mouseleave', () => { state.hi = null; applyStyle(); });
document.getElementById('all').onclick = () => { ORDER.forEach(s => state.on[s] = true); applyStyle(); };
document.getElementById('none').onclick = () => { ORDER.forEach(s => state.on[s] = false); applyStyle(); };

// crosshair tooltip: nearest sample of every visible series at the hovered time
const tip = document.getElementById('tip');
function placeTip(ev) {
  tip.hidden = false;
  const w = tip.offsetWidth, h = tip.offsetHeight;
  let L = ev.clientX + 16; if (L + w > innerWidth - 8) L = ev.clientX - w - 16;
  let T = ev.clientY - h/2; T = Math.max(8, Math.min(T, innerHeight - h - 8));
  tip.style.left = Math.max(8, L) + 'px'; tip.style.top = T + 'px';
}
function nearest(rows, x) { let lo = 0, hi = rows.length - 1;
  while (lo < hi) { const mid = (lo + hi) >> 1; if (rows[mid][0] < x) lo = mid + 1; else hi = mid; }
  const c = [rows[lo], rows[lo-1]].filter(Boolean).sort((a,b) => Math.abs(a[0]-x) - Math.abs(b[0]-x))[0];
  return c && Math.abs(c[0]-x) <= 300 ? c : null; }
charts.forEach((c, k) => {
  const cv = c.canvas;
  const move = ev => {
    const r = cv.getBoundingClientRect(), px = ev.clientX - r.left, a = c.chartArea;
    if (px < a.left || px > a.right) { hide(); return; }
    const x = c.scales.x.getValueForPixel(px);
    charts.forEach(o => { o.$cx = o.scales.x.getPixelForValue(x); o.draw(); });
    const rows = ORDER.map((s, i) => ({s, i, r: state.on[s] ? nearest(D.s[s], x) : null})).filter(o => o.r)
      .sort((p, q) => q.r[METRICS[k].i] - p.r[METRICS[k].i]);
    tip.innerHTML = `<div class="t">${METRICS[k].name} · ${fmtT(x)}</div>` + (rows.length ? rows.map(o =>
      `<div class="r"><span>${swatch(o.i,o.s)}${o.s}</span><b>${mb(o.r[METRICS[k].i]).toFixed(1)} MB</b></div>`).join('') : '<div class="t">이 시점 값 없음</div>');
    placeTip(ev);
  };
  const hide = () => { tip.hidden = true; charts.forEach(o => { o.$cx = null; o.draw(); }); };
  cv.addEventListener('mousemove', move); cv.addEventListener('mouseleave', hide);
  cv.addEventListener('touchstart', e => move(e.touches[0]), {passive: true});
  cv.addEventListener('touchmove', e => move(e.touches[0]), {passive: true});
  cv.addEventListener('touchend', hide);
});

// summary table
const avg = (rows, i, from, to) => { const v = rows.filter(r => r[0] >= from && r[0] < to).map(r => r[i]); return v.length ? mb(v.reduce((a,b)=>a+b,0)/v.length) : NaN; };
let t = '<thead><tr><th></th><th colspan="4">TOTAL PSS</th><th colspan="4">Native Heap Size</th><th colspan="4">Dalvik Heap Size</th><th></th><th></th></tr><tr><th>시료</th>';
for (let k = 0; k < 3; k++) t += '<th>시작</th><th>종료</th><th>증감</th><th>최대</th>';
t += '<th>재시작</th><th>누락</th></tr></thead><tbody>';
ORDER.forEach((s, i) => {
  const rows = D.s[s];
  t += `<tr><td>${swatch(i,s)} ${s}</td>`;
  METRICS.forEach(m => {
    const a = avg(rows, m.i, 0, 3600), b = avg(rows, m.i, SPAN-3600, SPAN+1), mx = mb(Math.max(...rows.map(r => r[m.i]))), d = b - a;
    t += `<td>${a.toFixed(0)}</td><td>${b.toFixed(0)}</td><td class="${d>0?'up':''}">${d>0?'+':''}${d.toFixed(0)}</td><td>${mx.toFixed(0)}</td>`;
  });
  let rs = 0; for (let j = 1; j < rows.length; j++) if (rows[j][4] !== rows[j-1][4]) rs++;
  t += `<td>${rs}</td><td>${D.miss[s]}</td></tr>`;
});
document.getElementById('tbl').innerHTML = t + '</tbody>';

applyStyle();
let v0 = 'sample'; try { v0 = localStorage.getItem('skbtv-view') || 'sample'; } catch (e) {}
setView(v0 === 'metric' ? 'metric' : 'sample');
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', applyStyle);
new MutationObserver(applyStyle).observe(document.documentElement, {attributes: true, attributeFilter: ['data-theme']});
</script>
'''

if __name__ == '__main__':
    main()
