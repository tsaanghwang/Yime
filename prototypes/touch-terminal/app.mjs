import {createSession} from './core.mjs';
import {geometry, missProbability, percentile} from './geometry.mjs';

const $ = id => document.getElementById(id);
const text = (tag, value, className) => { const el = document.createElement(tag); el.textContent = value; if (className) el.className = className; return el; };
let layout, demo, session, trace = [], latencies = [], touches = [], active = null, drill = null, guided = null;
let counter = 0;
const keyButtons = new Map();

function status(message) { $('status').textContent = message; }
function focusBoard() { $('keyboard').focus({preventScroll:true}); }
function dispatch(type, payload = {}, message = '') {
  const start = performance.now();
  const state = session.state;
  const event = {version:1, sessionId:state.sessionId, eventId:`event-${++counter}`, seq:state.nextSeq, layoutId:layout.layoutId, baseRevision:state.revision, type, payload};
  const result = session.dispatch(event);
  trace.push({event, result});
  if (trace.length > 100) trace.shift();
  render();
  if (!result.ok) status(`操作未执行：${JSON.stringify(result.error)}`);
  else if (message) status(message);
  else if (result.commit) status(`已确认「${result.commit.text}」，仅写入本页预览。`);
  else status(`已处理 ${type} · 组合修订 ${result.state.revision}`);
  requestAnimationFrame(() => {
    latencies.push(performance.now() - start);
    if (latencies.length > 1000) latencies.shift();
    $('latency').textContent = `事件处理 → 下一帧：p50 ${percentile(latencies,.5).toFixed(1)} / p95 ${percentile(latencies,.95).toFixed(1)} ms（最近 ${latencies.length} 次；非触控端到端延迟）`;
  });
  return result;
}

function pressSound(id, pointerType = 'keyboard') {
  const intended = drill && drill.attempts < 20 ? drill.targets[drill.attempts] : null;
  if (intended) {
    drill.attempts++;
    if (intended === id) drill.correct++; else drill.wrong++;
  }
  touches.push({id, intended, pointerType, cancelled:false, timeMs:Math.round(performance.now())});
  if (touches.length > 1000) touches.shift();
  dispatch('input', {yinyuanId:id});
  renderDrill();
}

function cancelPointer(reason) {
  if (!active) return;
  const previous = active;
  active = null;
  previous.button.classList.remove('pressed');
  touches.push({id:previous.id, pointerType:previous.pointerType, cancelled:true, reason, timeMs:Math.round(performance.now())});
  if (touches.length > 1000) touches.shift();
  if (drill && drill.attempts < 20) drill.cancelled++;
  renderDrill();
  status('本次触摸已取消，没有输入音元。');
}

function buildKeyboard() {
  for (const key of layout.keys) {
    const button = document.createElement('button');
    button.className = `sound-key${key.id.startsWith('M') ? ' musical' : ''}`;
    button.dataset.id = key.id;
    button.setAttribute('aria-label', `${key.id} ${key.name}，物理键 ${key.key}`);
    button.title = `${key.name} · ${key.group}${key.sharedWith?.length ? ` · 与 ${key.sharedWith.join('、')} 共享物理投影` : ''}`;
    button.append(text('span',key.id,'key-id'),text('span',key.label,'key-label'),text('span',`${key.shift ? '⇧ ' : ''}${key.physicalKey}`,'key-meta'));
    button.addEventListener('pointerdown', event => {
      if (event.button !== 0 || !event.isPrimary || active) return;
      event.preventDefault();
      $('keyboard').focus({preventScroll:true});
      active = {pointerId:event.pointerId, id:key.id, button, pointerType:event.pointerType, left:false};
      button.classList.add('pressed');
      button.setPointerCapture(event.pointerId);
    });
    button.addEventListener('pointermove', event => {
      if (active?.pointerId !== event.pointerId) return;
      const r = button.getBoundingClientRect();
      if (event.clientX < r.left || event.clientX >= r.right || event.clientY < r.top || event.clientY >= r.bottom) {
        active.left = true;
        button.classList.remove('pressed');
      }
    });
    button.addEventListener('pointerup', event => {
      if (active?.pointerId !== event.pointerId) return;
      const r = button.getBoundingClientRect();
      if (active.left || event.clientX < r.left || event.clientX >= r.right || event.clientY < r.top || event.clientY >= r.bottom) { cancelPointer('left-key'); return; }
      active = null;
      button.classList.remove('pressed');
      pressSound(key.id, event.pointerType);
    });
    button.addEventListener('pointercancel', event => { if (active?.pointerId === event.pointerId) cancelPointer('pointercancel'); });
    button.addEventListener('lostpointercapture', event => { if (active?.pointerId === event.pointerId) cancelPointer('lostpointercapture'); });
    // Pointer path already dispatched on release; only native keyboard/AT click remains.
    button.addEventListener('click', event => { if (event.detail === 0 && !event.pointerType) pressSound(key.id); });
    $('keyboard').append(button);
    keyButtons.set(key.id, button);
  }
  $('keyboard').addEventListener('keydown', event => {
    if (event.ctrlKey || event.altKey || event.metaKey || event.isComposing) return;
    // Preserve native Enter/Space activation when a specific key has keyboard focus.
    if (event.target.matches('button') && ['Enter',' '].includes(event.key)) return;
    const ordinal = event.shiftKey && /^Digit[1-9]$/.test(event.code) ? Number(event.code.slice(-1)) - 1 : -1;
    const mapped = layout.keys.find(key => key.key === event.key);
    if (ordinal < 0 && !mapped && !['Backspace','Enter','Escape','PageUp','PageDown'].includes(event.key)) return;
    event.preventDefault();
    if (event.repeat) return;
    if (ordinal >= 0) {
      const candidate = session.state.candidates[ordinal];
      if (candidate) dispatch('select',{candidateId:candidate.id}, '候选已选中；按确认写入本页。');
    } else if (event.key === 'Backspace') dispatch('backspace');
    else if (event.key === 'Enter') dispatch('confirm');
    else if (event.key === 'Escape') dispatch('clear');
    else if (event.key === 'PageUp') dispatch('page',{delta:-1});
    else if (event.key === 'PageDown') dispatch('page',{delta:1});
    else if (mapped) {
      pressSound(mapped.id);
      if (mapped.sharedWith?.length) status(`物理键采用主 ID ${mapped.id}；独立音元请点击其触摸键。`);
    }
  });
}

function render() {
  const state = session.state;
  $('committed').textContent = state.committed.map(c => c.text).join('') || '等待第一次确认';
  $('composition').textContent = state.ids.map(id => `${id} ${layout.keys.find(k => k.id === id).label}`).join(' · ') || '点击下方音元开始';
  $('code').textContent = state.code || '—';
  $('candidates').replaceChildren();
  if (!state.candidates.length) $('candidates').append(text('p', state.ids.length ? '没有匹配的固定样例；可继续输入、退格或清空。' : '输入完整样例后展示候选。','hint'));
  state.candidates.forEach((candidate, index) => {
    const button = document.createElement('button');
    button.className = `candidate${candidate.id === state.selectedId ? ' selected' : ''}`;
    button.dataset.candidateId = candidate.id;
    button.setAttribute('aria-pressed', String(candidate.id === state.selectedId));
    button.append(text('span',`⇧${index+1}`,'ordinal'), text('span',candidate.text));
    button.addEventListener('click', () => { dispatch('select',{candidateId:candidate.id}, '候选已选中；按确认写入本页。'); focusBoard(); });
    $('candidates').append(button);
  });
  $('confirm').disabled = !state.selectedId;
  $('backspace').disabled = !state.ids.length;
  $('clear').disabled = !state.ids.length;
  $('prev').disabled = state.page <= 0;
  $('next').disabled = state.page + 1 >= state.pageCount;
  $('page-label').textContent = state.pageCount ? `${state.page + 1} / ${state.pageCount} 页` : '等待组合';
  $('trace').textContent = JSON.stringify(trace.slice(-2), null, 2);
  if (guided) {
    const matches = state.ids.every((id,i) => guided.ids[i] === id);
    const next = matches ? guided.ids[state.ids.length] : null;
    $('guide').textContent = `「${guided.label}」顺序：${guided.ids.join(' → ')}。${next ? `下一键：${next}` : matches ? '音元已齐，可选择候选并确认。' : '当前组合不同，可退格或重新载入。'}`;
  }
  renderDrill();
}

function renderDrill() {
  const target = drill && drill.attempts < 20 ? drill.targets[drill.attempts] : null;
  for (const [id,button] of keyButtons) button.classList.toggle('target', id === target);
  if (!drill) return;
  $('drill-status').textContent = `${target ? `请点 ${target} · ` : '本轮完成 · '}已点 ${drill.attempts}/20，命中 ${drill.correct}，错键 ${drill.wrong}，取消 ${drill.cancelled}。${drill.attempts ? `错键率 ${(100 * drill.wrong / drill.attempts).toFixed(1)}%（仅本轮输入设备）` : ''}`;
}

function updateGeometry() {
  const diagonal = Number($('diagonal').value), g = geometry(diagonal);
  $('diagonal-value').textContent = `${diagonal.toFixed(1)}″`;
  $('key-size').textContent = `${g.keyWidth.toFixed(1)} × ${g.keyHeight.toFixed(1)}`;
  $('miss-model').textContent = `${(100 * missProbability(g.keyWidth,g.keyHeight,2)).toFixed(2)}%`;
  $('size-advice').textContent = Math.min(g.keyWidth,g.keyHeight) < 9 ? '短边低于 9 mm 假设目标：优先验证窄键误触。' : '达到短边 ≥9 mm 的试制假设；仍需真人触屏验证。';
  const rect = keyButtons.values().next().value?.getBoundingClientRect();
  if (rect) $('actual-size').textContent = `当前浏览器实际键面约 ${rect.width.toFixed(0)} × ${rect.height.toFixed(0)} CSS px。窗口窄时横向滚动，保持 60 键排列。`;
}

async function init() {
  [layout, demo] = await Promise.all(['layout','demo'].map(async file => {
    const response = await fetch(`./data/${file}.json`);
    if (!response.ok) throw new Error(`${file}: HTTP ${response.status}`);
    return response.json();
  }));
  session = createSession(layout, demo, crypto.randomUUID());
  buildKeyboard();
  for (const example of demo.examples) {
    const button = text('button',`载入 ${example.label}`);
    button.dataset.exampleId = example.id;
    button.addEventListener('click', () => {
      guided = example;
      dispatch('clear');
      for (const id of example.ids) dispatch('input',{yinyuanId:id});
      status('已载入固定样例；点击候选，再按确认。');
      focusBoard();
    });
    $('examples').append(button);
  }
  guided = demo.examples[0];
  for (const [id,type,payload] of [['backspace','backspace',{}],['clear','clear',{}],['confirm','confirm',{}],['prev','page',{delta:-1}],['next','page',{delta:1}]]) {
    $(id).addEventListener('click', () => { dispatch(type,payload); focusBoard(); });
  }
  $('diagonal').addEventListener('input', updateGeometry);
  window.addEventListener('resize', updateGeometry);
  window.addEventListener('blur', () => { cancelPointer('window-blur'); if (session.state.ids.length) dispatch('clear',{},'页面失焦：未确认组合已取消，已确认预览保留。'); });
  document.addEventListener('visibilitychange', () => { if (document.hidden) { cancelPointer('page-hidden'); if (session.state.ids.length) dispatch('clear'); } });
  $('drill').addEventListener('click', () => {
    dispatch('clear');
    drill = {targets:Array.from({length:20},(_,i) => layout.keys[(i * 17 + 3) % layout.keys.length].id),attempts:0,correct:0,wrong:0,cancelled:0};
    renderDrill();
  });
  $('export').addEventListener('click', () => {
    const report = {formatVersion:1,mode:'offline-mock',createdAt:new Date().toISOString(),layoutId:layout.layoutId,sources:[...layout.sources,...demo.sources],screenAssumption:{diagonalInches:Number($('diagonal').value),...geometry(Number($('diagonal').value))},viewport:{width:innerWidth,height:innerHeight,devicePixelRatio},drill,touches,handlerToNextFrameMs:latencies,trace,limits:{trace:100,touches:1000,latency:1000},note:'仅本页记录；非真实输入法、触控误触率或contact-to-photon验收。'};
    const url = URL.createObjectURL(new Blob([JSON.stringify(report,null,2)],{type:'application/json'}));
    const anchor = document.createElement('a'); anchor.href = url; anchor.download = 'yime-touch-session.json'; anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    status('已导出本页记录；未读取系统或输入法用户数据。');
  });
  $('layout-id').textContent = `layoutId：${layout.layoutId} · ${layout.keys.length} 独立音元 / ${new Set(layout.keys.map(k=>k.key)).size} 物理投影字符`;
  for (const source of [...layout.sources,...demo.sources]) $('sources').append(text('li',`${source.path} · SHA-256（${source.hashMode}）${source.sha256}`));
  render(); updateGeometry(); status('就绪。可逐键输入右侧引导样例，或点击“载入”。');
}
init().catch(error => { $('load-error').hidden = false; $('load-error').textContent = `原型未就绪：${error.message}。请通过 serve.py 打开本地 HTTP 地址，并运行数据校验。`; status('加载失败，输入不可用。'); console.error(error); });
