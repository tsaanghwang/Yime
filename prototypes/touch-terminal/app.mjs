import {createSession} from './core.mjs';
import {geometry, missProbability, percentile} from './geometry.mjs';

const $ = id => document.getElementById(id);
const text = (tag, value, className) => { const el = document.createElement(tag); el.textContent = value; if (className) el.className = className; return el; };
let layout, demo, session, trace = [], latencies = [], touches = [], active = null, drill = null, guided = null;
const drills = [];
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

function pressSound(id, pointerType = 'keyboard', pointer = null) {
  let intended = null, drillResult = null;
  if (drill?.kind === 'coverage-all-keys-any-order' && drill.unique < drill.targets.length) {
    drill.attempts++;
    if (drill.seen.includes(id)) {
      drill.duplicate++;
      drillResult = 'duplicate';
    } else {
      drill.seen.push(id);
      drill.unique++;
      drillResult = 'new-key';
    }
  } else if (drill?.kind === 'prompted-targets-retry-until-correct' && drill.correct < drill.targets.length) {
    intended = drill.targets[drill.correct];
    drill.attempts++;
    if (intended === id) { drill.correct++; drillResult = 'correct'; }
    else { drill.wrong++; drillResult = 'wrong-key'; }
  }
  touches.push({id, intended, drillKind:drill?.kind || null, drillResult, pointerType, cancelled:false, timeMs:Math.round(performance.now()), ...(pointer ? {pointer} : {})});
  if (touches.length > 1000) touches.shift();
  dispatch('input', {yinyuanId:id});
  renderDrill();
}

function pointerSample(event, rect) {
  return {
    clientCssPx:{x:event.clientX,y:event.clientY},
    contactCssPx:{width:event.width,height:event.height},
    pressure:event.pressure,
    keyRectCssPx:{left:rect.left,top:rect.top,width:rect.width,height:rect.height},
    keyLocal:{x:(event.clientX-rect.left)/rect.width,y:(event.clientY-rect.top)/rect.height}
  };
}

function cancelPointer(reason, event = null) {
  if (!active) return;
  const previous = active;
  active = null;
  previous.button.classList.remove('pressed');
  const rect = previous.button.getBoundingClientRect();
  const up = event ? pointerSample(event,rect) : null;
  touches.push({id:previous.id, intended:drill?.kind === 'prompted-targets-retry-until-correct' ? drill.targets[drill.correct] || null : null, drillKind:drill?.kind || null, drillResult:'cancelled', pointerType:previous.pointerType, cancelled:true, reason, timeMs:Math.round(performance.now()), pointer:{down:previous.down, ...(up ? {up} : {}), holdMs:Math.round(performance.now()-previous.startedAt)}});
  if (touches.length > 1000) touches.shift();
  if (drill && ((drill.kind === 'coverage-all-keys-any-order' && drill.unique < drill.targets.length) || (drill.kind === 'prompted-targets-retry-until-correct' && drill.correct < drill.targets.length))) drill.cancelled++;
  renderDrill();
  status('本次触摸已取消，没有输入音元。');
}

function buildKeyboard() {
  const board = $('keyboard');
  const bounds = layout.touchTemplate.bounds;
  board.style.setProperty('--touch-aspect', `${bounds.width}/${bounds.height}`);
  for (const key of layout.keys) {
    const button = document.createElement('button');
    button.className = `sound-key${key.id.startsWith('M') ? ' musical' : ''}`;
    button.dataset.id = key.id;
    const touch = key.touch;
    const left = 100 * touch.x / bounds.width;
    const top = 100 * touch.y / bounds.height;
    const width = 100 * touch.width / bounds.width;
    const height = 100 * touch.height / bounds.height;
    button.style.left = `calc(${left}% + 3px)`;
    button.style.top = `calc(${top}% + 3px)`;
    button.style.width = `calc(${width}% - 6px)`;
    button.style.height = `calc(${height}% - 6px)`;
    button.style.setProperty('--touch-key-color', touch.color);
    button.style.setProperty('--touch-text-color', touch.textColor);
    button.setAttribute('aria-label', `${key.id} ${key.name}，物理键 ${key.key}`);
    button.title = `${key.name} · ${key.group}${key.sharedWith?.length ? ` · 与 ${key.sharedWith.join('、')} 共享物理投影` : ''}`;
    button.append(text('span',key.id,'key-id'),text('span',key.label,'key-label'),text('span',`${key.shift ? '⇧ ' : ''}${key.physicalKey}`,'key-meta'));
    button.addEventListener('pointerdown', event => {
      if (event.button !== 0 || !event.isPrimary || active) return;
      event.preventDefault();
      $('keyboard').focus({preventScroll:true});
      const rect = button.getBoundingClientRect();
      active = {pointerId:event.pointerId, id:key.id, button, pointerType:event.pointerType, left:false, startedAt:performance.now(), down:pointerSample(event,rect)};
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
      if (active.left || event.clientX < r.left || event.clientX >= r.right || event.clientY < r.top || event.clientY >= r.bottom) { cancelPointer('left-key',event); return; }
      const completed = active;
      active = null;
      button.classList.remove('pressed');
      pressSound(key.id, event.pointerType, {down:completed.down,up:pointerSample(event,r),holdMs:Math.round(performance.now()-completed.startedAt)});
    });
    button.addEventListener('pointercancel', event => { if (active?.pointerId === event.pointerId) cancelPointer('pointercancel',event); });
    button.addEventListener('lostpointercapture', event => { if (active?.pointerId === event.pointerId) cancelPointer('lostpointercapture',event); });
    // Pointer path already dispatched on release; only native keyboard/AT click remains.
    button.addEventListener('click', event => { if (event.detail === 0 && !event.pointerType) pressSound(key.id); });
    board.append(button);
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

function screenEnvironment() {
  const orientation = screen.orientation ? {type:screen.orientation.type, angle:screen.orientation.angle} : null;
  return {
    screenCssPx:{width:screen.width,height:screen.height,availWidth:screen.availWidth,availHeight:screen.availHeight},
    viewportCssPx:{width:innerWidth,height:innerHeight},
    devicePixelRatio,
    maxTouchPoints:navigator.maxTouchPoints || 0,
    coarsePointer:matchMedia('(pointer: coarse)').matches,
    anyCoarsePointer:matchMedia('(any-pointer: coarse)').matches,
    orientation
  };
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
  const target = drill?.kind === 'prompted-targets-retry-until-correct' && drill.correct < drill.targets.length ? drill.targets[drill.correct] : null;
  const seen = new Set(drill?.seen || []);
  for (const [id,button] of keyButtons) {
    button.classList.toggle('target', id === target);
    button.classList.toggle('visited', drill?.kind === 'coverage-all-keys-any-order' && seen.has(id));
  }
  if (!drill) { $('drill-target').textContent = '尚未开始'; return; }
  if (drill.kind === 'coverage-all-keys-any-order') {
    $('drill-target').textContent = drill.unique === drill.targets.length ? '覆盖完成' : '任意顺序：点尚未变暗的键';
    $('drill-status').textContent = `已覆盖 ${drill.unique}/${drill.targets.length}，总点按 ${drill.attempts}，重复 ${drill.duplicate}，取消 ${drill.cancelled}。`;
  } else {
    $('drill-target').textContent = target ? `当前目标：${target}` : '目标准确度完成';
    $('drill-status').textContent = `${target ? '请只点橙框目标；错键后目标保持不变 · ' : '本轮完成 · '}已完成 ${drill.correct}/${drill.targets.length} 个目标，总点按 ${drill.attempts}，错键 ${drill.wrong}，取消 ${drill.cancelled}。${drill.attempts ? `错键率 ${(100 * drill.wrong / drill.attempts).toFixed(1)}%（仅本轮输入设备）` : ''}`;
  }
}

function startDrill(next) {
  dispatch('clear');
  drill = next;
  drills.push(drill);
  renderDrill();
}

function updateGeometry() {
  const diagonal = Number($('diagonal').value), environment = screenEnvironment();
  const bounds = layout.touchTemplate.bounds;
  const g = geometry(diagonal, 2, environment.screenCssPx.width, environment.screenCssPx.height, bounds.width, bounds.height);
  $('diagonal-value').textContent = `${diagonal.toFixed(1)}″`;
  $('key-size').textContent = `${g.keyWidth.toFixed(1)} × ${g.keyHeight.toFixed(1)}`;
  $('miss-model').textContent = `${(100 * missProbability(g.keyWidth,g.keyHeight,2)).toFixed(2)}%`;
  $('size-advice').textContent = Math.min(g.keyWidth,g.keyHeight) < 9 ? '短边低于 9 mm 假设目标：优先验证窄键误触。' : '达到短边 ≥9 mm 的试制假设；仍需真人触屏验证。';
  const rect = keyButtons.values().next().value?.getBoundingClientRect();
  $('environment').textContent = `浏览器检测：screen ${environment.screenCssPx.width} × ${environment.screenCssPx.height} CSS px，DPR ${environment.devicePixelRatio}，maxTouchPoints ${environment.maxTouchPoints}，coarse pointer ${environment.anyCoarsePointer ? '是' : '否'}。复制显示模式无法由页面独立核实。`;
  if (rect) $('actual-size').textContent = `当前第一个 KLE 1u 键面约 ${rect.width.toFixed(0)} × ${rect.height.toFixed(0)} CSS px。窗口窄时横向滚动，保持模板几何。`;
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
    startDrill({kind:'coverage-all-keys-any-order',targets:layout.keys.map(key => key.id),attempts:0,unique:0,duplicate:0,cancelled:0,seen:[]});
  });
  $('target-drill').addEventListener('click', () => startDrill({kind:'prompted-targets-retry-until-correct',advanceOn:'correct',targets:Array.from({length:layout.keys.length},(_,i) => layout.keys[(i * 17 + 3) % layout.keys.length].id),attempts:0,correct:0,wrong:0,cancelled:0}));
  $('export').addEventListener('click', () => {
    const environment = screenEnvironment();
    const bounds = layout.touchTemplate.bounds;
    const report = {formatVersion:3,mode:'offline-touch-baseline',createdAt:new Date().toISOString(),layoutId:layout.layoutId,touchTemplateId:layout.touchTemplate.id,touchTemplate:layout.touchTemplate,sources:[...layout.sources,...demo.sources],screenAssumption:{diagonalInches:Number($('diagonal').value),...geometry(Number($('diagonal').value),2,environment.screenCssPx.width,environment.screenCssPx.height,bounds.width,bounds.height)},environment,drills,drill,touches,handlerToNextFrameMs:latencies,trace,limits:{trace:100,touches:1000,latency:1000},hardwareAcceptance:false,note:'真实 pointerType、浏览器触点坐标/接触面积与页面处理代理值；未尺测、未高速相机测量时，不是触控误触率、contact-to-photon 或输入法验收。'};
    const url = URL.createObjectURL(new Blob([JSON.stringify(report,null,2)],{type:'application/json'}));
    const anchor = document.createElement('a'); anchor.href = url; anchor.download = 'yime-touch-session.json'; anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    status('已导出本页记录；未读取系统或输入法用户数据。');
  });
  const bounds = layout.touchTemplate.bounds;
  $('touch-template-label').textContent = `${bounds.width} × ${bounds.height} KLE u`;
  $('layout-id').textContent = `layoutId：${layout.layoutId} · touchTemplateId：${layout.touchTemplate.id} · ${layout.keys.length} 独立音元 / ${new Set(layout.keys.map(k=>k.key)).size} 桌面投影字符`;
  for (const source of [...layout.sources,...demo.sources]) $('sources').append(text('li',`${source.path} · SHA-256（${source.hashMode}）${source.sha256}`));
  render(); updateGeometry(); status('就绪。可逐键输入右侧引导样例，或点击“载入”。');
}
init().catch(error => { $('load-error').hidden = false; $('load-error').textContent = `原型未就绪：${error.message}。请通过 serve.py 打开本地 HTTP 地址，并运行数据校验。`; status('加载失败，输入不可用。'); console.error(error); });
