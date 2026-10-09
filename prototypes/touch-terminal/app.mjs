import {actionFromKeyboard,createLiveClient,editText,samePointerRelease} from './input.mjs';
import {percentile} from './geometry.mjs';

const $ = id => document.getElementById(id);
const node = (tag,value,className) => {
  const element = document.createElement(tag);
  element.textContent = value;
  if (className) element.className = className;
  return element;
};
let layout, client, active = null, trace = [], touches = [], latencies = [], drill = null;
const keyButtons = new Map(), drills = [];
const status = message => { $('status').textContent = message; };
const focusBoard = () => $('keyboard').focus({preventScroll:true});
const currentState = () => client?.snapshot?.state || {raw_input:'',candidates:[],page_number:0};

function appendCommit(value) {
  const surface = $('committed');
  surface.setRangeText(value,surface.selectionStart,surface.selectionEnd,'end');
  surface.dispatchEvent(new Event('input',{bubbles:true}));
}

function render(result, event) {
  if (result.commit) appendCommit(result.commit);
  const state = result.state, candidates = state.candidates || [];
  $('code').textContent = state.raw_input || '—';
  $('composition').textContent = state.raw_input ? '正在组合；候选来自当前码制的 Go 引擎。' : '点按编码键，或在这里使用 ANSI 键盘。';
  $('candidates').replaceChildren();
  if (!candidates.length) $('candidates').append(node('p',state.raw_input ? '当前编码暂无候选，可继续输入、退格或取消。' : '候选将显示在这里。','hint'));
  candidates.forEach((candidate,index) => {
    const button = document.createElement('button');
    button.className = 'candidate';
    button.dataset.candidateId = candidate.id;
    button.append(node('span',String(index+1),'ordinal'),node('span',candidate.text));
    button.title = `候选 ${index+1} · ANSI 直接按 ${index+1}`;
    button.addEventListener('click',() => {
      perform({type:'select',candidateId:candidate.id},'candidate');
      focusBoard();
    });
    $('candidates').append(button);
  });
  $('confirm').disabled = !candidates.length;
  $('clear').disabled = !state.raw_input;
  $('prev').disabled = !state.has_previous;
  $('next').disabled = !state.has_next;
  $('page-label').textContent = candidates.length ? `第 ${(state.page_number || 0)+1} 页` : '';
  $('connection').textContent = 'Go 引擎已连接 · 仅本页文本';
  $('connection').classList.add('connected');
  if (event) {
    trace.push({event,result});
    if (trace.length > 100) trace.shift();
    $('trace').textContent = JSON.stringify(trace.slice(-2),null,2);
  }
}

function localEdit(key) {
  if (currentState().raw_input) {
    status('请先选词或取消当前组合，再编辑已确认文本。');
    return;
  }
  const surface = $('committed');
  const next = editText(surface.value,surface.selectionStart,surface.selectionEnd,key);
  if (next) {
    surface.value = next.value;
    surface.setSelectionRange(next.start,next.end);
    status(`已在本页文本中处理 ${key}。`);
  } else status(`${key} 仅保留实体键位：当前页面不模拟这个系统功能。`);
}

let actions = Promise.resolve();
function perform(action,source='virtual') {
  // Serialize the entire action, including local text edits, so a quick sequence
  // cannot inspect composition state before the preceding input response arrives.
  actions = actions.then(() => performOne(action,source)).catch(error => status(`操作未完成：${error.message}`));
  return actions;
}
async function performOne(action,source) {
  if (!action) return;
  if (action.type === 'unsupported') {
    status(`${action.label || '此键'} 仅保留实体键位；没有发送系统快捷键。`);
    return;
  }
  if (action.type === 'local') { localEdit(action.key); return; }
  if (!client.connected) { status('引擎未连接，请使用项目的本地服务并刷新页面。'); return; }
  if (action.type === 'confirm' && !currentState().raw_input) { localEdit(action.key || 'Space'); return; }
  if (action.type === 'backspace' && !currentState().raw_input) { localEdit('Backspace'); return; }
  const start = performance.now();
  try {
    const result = await client.dispatch(action);
    if (!result) status('当前没有可选候选，或已到候选页边界。');
    else if (result.commit) status(`已确认「${result.commit}」，写入本页文本。`);
    else status(`${source === 'ansi' ? 'ANSI' : '虚拟键'} · ${action.type === 'input' ? `输入 ${JSON.stringify(action.ascii)}` : '操作完成'}`);
    requestAnimationFrame(() => {
      latencies.push(performance.now()-start);
      if (latencies.length > 1000) latencies.shift();
      $('latency').textContent = `请求 → 下一帧 p50 ${percentile(latencies,.5).toFixed(1)} / p95 ${percentile(latencies,.95).toFixed(1)} ms（非端到端触控延迟）`;
    });
  } catch (error) {
    status(`操作未完成：${error.message}`);
    $('connection').textContent = '连接中断 · 请刷新重新连接';
    $('connection').classList.remove('connected');
  }
}

function pointerSample(event,rect) {
  return {clientCssPx:{x:event.clientX,y:event.clientY},contactCssPx:{width:event.width,height:event.height},pressure:event.pressure,
    keyRectCssPx:{left:rect.left,top:rect.top,width:rect.width,height:rect.height},
    keyLocal:{x:(event.clientX-rect.left)/rect.width,y:(event.clientY-rect.top)/rect.height}};
}
function drillActive() {
  return drill && (drill.kind === 'coverage' ? drill.seen.length < drill.targets.length : drill.correct < drill.targets.length);
}
function recordKey(key,pointerType,pointer,cancelled=false,reason=null) {
  const running = drillActive();
  let outcome = null, intended = null;
  if (running) {
    if (cancelled) { drill.cancelled++; outcome = 'cancelled'; }
    else {
      drill.attempts++;
      if (drill.kind === 'coverage') {
        outcome = drill.seen.includes(key.id) ? 'duplicate' : 'new-key';
        if (outcome === 'duplicate') drill.duplicate++; else drill.seen.push(key.id);
      } else {
        intended = drill.targets[drill.correct];
        outcome = intended === key.id ? 'correct' : 'wrong-key';
        if (outcome === 'correct') drill.correct++; else drill.wrong++;
      }
    }
  }
  touches.push({physicalKeyId:key.id,yinyuanIds:key.yinyuanIds,action:key.action,pointerType,pointer,cancelled,reason,
    drillKind:running ? drill.kind : null,drillResult:outcome,intended,timeMs:Math.round(performance.now())});
  if (touches.length > 1000) touches.shift();
  renderDrill();
  // Coverage drills test geometry without altering the local test document.
  if (!cancelled && !running) perform(key.action);
}
function cancelPointer(reason,event=null) {
  if (!active) return;
  const previous = active;
  active = null;
  previous.button.classList.remove('pressed');
  const rect = previous.button.getBoundingClientRect();
  recordKey(previous.key,previous.pointerType,{down:previous.down,...(event ? {up:pointerSample(event,rect)} : {}),holdMs:Math.round(performance.now()-previous.startedAt)},true,reason);
  status('点按已取消，没有发送按键动作。');
}

// Decode entities as textarea text after removing markup. An inert HTML document
// could still fetch an embedded image; no source tags are parsed into elements.
function legendText(value) {
  const decoder = document.createElement('textarea');
  decoder.innerHTML = String(value).replace(/<[^>]*>/g,'');
  return decoder.value;
}
function addLegend(button,value,index,key) {
  if (!value) return;
  const span = document.createElement('span');
  span.className = `key-legend legend-${index}`;
  const disabled = new Set(key.disabledYinyuanIds || []);
  const label = legendText(value);
  if (/^[MN]\d{2}(?:\|[MN]\d{2})+$/.test(label)) span.classList.add('shared-legend');
  for (const part of label.split(/([MN]\d{2})/g)) {
    if (disabled.has(part)) span.append(node('span',part,'disabled-yinyuan'));
    else span.append(document.createTextNode(part));
  }
  button.append(span);
}
function buildKeyboard() {
  const board = $('keyboard'), bounds = layout.bounds;
  board.style.setProperty('--keyboard-ratio',`${bounds.width}/${bounds.height}`);
  board.style.setProperty('--keyboard-min-width',`${Math.ceil(bounds.width*54)}px`);
  for (const key of layout.keys) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `physical-key role-${key.action.type}`;
    button.dataset.id = key.id;
    button.dataset.ascii = key.action.ascii || '';
    button.dataset.action = key.action.type;
    button.dataset.yinyuanIds = (key.yinyuanIds || []).join(',');
    button.style.left = `calc(${100*key.x/bounds.width}% + 2px)`;
    button.style.top = `calc(${100*key.y/bounds.height}% + 2px)`;
    button.style.width = `calc(${100*key.width/bounds.width}% - 4px)`;
    button.style.height = `calc(${100*key.height/bounds.height}% - 4px)`;
    button.style.setProperty('--key-color',key.color || '#deded7');
    button.style.setProperty('--key-text',key.textColor || '#172c30');
    const labels = key.displayLabels || key.labels || [];
    const ids = (key.yinyuanIds || []).map(id => (key.disabledYinyuanIds || []).includes(id) ? `${id} 停用` : id).join('，');
    const description = key.action.type === 'input' ? `ASCII ${key.action.ascii}`
      : key.action.type === 'select' ? `候选 ${key.action.ordinal}（直接选择）`
      : key.action.label || key.action.key || key.action.type;
    button.setAttribute('aria-label',`${key.id} ${ids || labels.map(legendText).filter(Boolean).join(' ')}，${description}`);
    button.title = `${key.id} · ${description}${ids ? ` · ${ids}` : ''}`;
    labels.forEach((label,index) => addLegend(button,label,index,key));
    if (!labels.some(Boolean)) button.append(node('span','Space','key-space'));
    if (key.action.type === 'unsupported') button.append(node('span','仅示意','simulation-label'));
    button.addEventListener('pointerdown',event => {
      if (event.button !== 0 || !event.isPrimary || active) return;
      event.preventDefault();
      focusBoard();
      active = {pointerId:event.pointerId,key,button,pointerType:event.pointerType,left:false,startedAt:performance.now(),down:pointerSample(event,button.getBoundingClientRect())};
      button.classList.add('pressed');
      button.setPointerCapture(event.pointerId);
    });
    button.addEventListener('pointermove',event => {
      if (active?.pointerId !== event.pointerId) return;
      if (!samePointerRelease(active,event,button.getBoundingClientRect())) {
        active.left = true;
        button.classList.remove('pressed');
      }
    });
    button.addEventListener('pointerup',event => {
      if (active?.pointerId !== event.pointerId) return;
      const rect = button.getBoundingClientRect();
      if (!samePointerRelease(active,event,rect)) { cancelPointer('left-key',event); return; }
      const completed = active;
      active = null;
      button.classList.remove('pressed');
      recordKey(key,event.pointerType,{down:completed.down,up:pointerSample(event,rect),holdMs:Math.round(performance.now()-completed.startedAt)});
    });
    button.addEventListener('pointercancel',event => { if (active?.pointerId === event.pointerId) cancelPointer('pointercancel',event); });
    button.addEventListener('lostpointercapture',event => { if (active?.pointerId === event.pointerId) cancelPointer('lostpointercapture',event); });
    button.addEventListener('click',event => {
      if (event.detail === 0 && !event.pointerType) recordKey(key,'keyboard',null);
    });
    board.append(button);
    keyButtons.set(key.id,button);
  }
  $('touch-template-label').textContent = `${layout.keys.length} 键 · ${bounds.width} × ${bounds.height} KLE u`;
}

function keyboardInput(event) {
  if (event.target.matches('button') && ['Enter',' '].includes(event.key)) return;
  if (event.repeat && actionFromKeyboard({key:event.key,code:event.code,shiftKey:event.shiftKey,ctrlKey:event.ctrlKey,altKey:event.altKey,metaKey:event.metaKey,isComposing:event.isComposing})) {
    event.preventDefault();
    return;
  }
  const action = actionFromKeyboard(event);
  if (!action) return;
  // Tab preserves board navigation, but can edit a tab in the local textarea.
  if (event.key === 'Tab' && event.target !== $('committed')) return;
  event.preventDefault();
  if (action.type === 'confirm') action.key = event.key === 'Enter' ? 'Enter' : 'Space';
  perform(action,'ansi');
}
function renderDrill() {
  const running = drillActive(), target = running && drill.kind === 'targets' ? drill.targets[drill.correct] : null;
  for (const [id,button] of keyButtons) {
    button.classList.toggle('target',id === target);
    button.classList.toggle('visited',Boolean(running && drill.kind === 'coverage' && drill.seen.includes(id)));
  }
  if (!drill) { $('drill-target').textContent = '尚未开始'; return; }
  $('drill-target').textContent = !running ? '本轮完成' : target ? `当前目标：${target}` : '任意顺序点未变暗的键';
  $('drill-status').textContent = drill.kind === 'coverage'
    ? `已覆盖 ${drill.seen.length}/${drill.targets.length}，总点按 ${drill.attempts}，重复 ${drill.duplicate}，取消 ${drill.cancelled}。`
    : `完成 ${drill.correct}/${drill.targets.length}，总点按 ${drill.attempts}，错键 ${drill.wrong}，取消 ${drill.cancelled}。`;
}
function startDrill(kind) {
  cancelPointer('drill-start');
  perform({type:'clear'});
  const targets = kind === 'targets'
    ? layout.keys.map((_,i) => layout.keys[(i*17+3)%layout.keys.length].id)
    : layout.keys.map(key => key.id);
  drill = {kind,targets,seen:[],correct:0,attempts:0,wrong:0,duplicate:0,cancelled:0};
  drills.push(drill);
  renderDrill();
  status('点按测量期间仅记录命中，不发送编码或控制动作；完成本轮后自动恢复输入。');
}
function environment() {
  return {screenCssPx:{width:screen.width,height:screen.height},viewportCssPx:{width:innerWidth,height:innerHeight},
    devicePixelRatio,maxTouchPoints:navigator.maxTouchPoints || 0,anyCoarsePointer:matchMedia('(any-pointer: coarse)').matches};
}
function updateEnvironment() {
  const env = environment();
  $('environment').textContent = `屏幕 ${env.screenCssPx.width} × ${env.screenCssPx.height}；视口 ${env.viewportCssPx.width} × ${env.viewportCssPx.height} CSS px · DPR ${env.devicePixelRatio.toFixed(2)} · 最大触点 ${env.maxTouchPoints}。`;
}
function exportReport() {
  const report = {formatVersion:4,mode:'ascii-physical-keyboard',createdAt:new Date().toISOString(),layoutId:layout.layoutId,touchTemplateId:layout.touchTemplateId,
    sources:layout.sources,environment:environment(),disabledYinyuanIds:layout.disabledYinyuanIds,drills,touches,trace,handlerToNextFrameMs:latencies,
    hardwareAcceptance:false,note:'本页 Go 引擎与浏览器事件记录；不证明 Windows 注册宿主、实体键盘或真实触屏验收。'};
  const url = URL.createObjectURL(new Blob([JSON.stringify(report,null,2)],{type:'application/json'}));
  const anchor = document.createElement('a');
  anchor.href = url; anchor.download = 'yime-keyboard-session.json'; anchor.click();
  setTimeout(() => URL.revokeObjectURL(url),1000);
}

async function init() {
  if (location.protocol === 'file:') throw new Error('此版本需要本地 Go 服务。请按 README 启动服务后打开 http://127.0.0.1 对应地址；文件页面不能运行真实候选引擎。');
  const response = await fetch('./data/physical-layout.json',{cache:'no-store'});
  if (!response.ok) throw new Error(`布局读取失败：HTTP ${response.status}`);
  layout = await response.json();
  buildKeyboard();
  client = createLiveClient({onResult:render});
  $('keyboard').addEventListener('keydown',keyboardInput);
  $('committed').addEventListener('keydown',keyboardInput);
  for (const [id,action] of Object.entries({backspace:{type:'backspace'},clear:{type:'clear'},confirm:{type:'confirm'},prev:{type:'page',delta:-1},next:{type:'page',delta:1}})) {
    $(id).addEventListener('click',() => { perform(action); focusBoard(); });
  }
  $('code-mode').addEventListener('change',event => {
    cancelPointer('mode-change');
    event.target.disabled = true;
    actions = actions.then(async () => {
      try { await client.changeMode(event.target.value); status('已切换码制，未确认组合已取消。'); }
      catch (error) { status(`切换失败：${error.message}`); }
      finally { event.target.disabled = false; focusBoard(); }
    });
  });
  const cancelComposition = reason => {
    cancelPointer(reason);
    // Always enqueue after pending input, even before its response is visible.
    perform({type:'clear'});
  };
  window.addEventListener('blur',() => cancelComposition('window-blur'));
  document.addEventListener('visibilitychange',() => { if (document.hidden) cancelComposition('page-hidden'); });
  $('drill').addEventListener('click',() => startDrill('coverage'));
  $('target-drill').addEventListener('click',() => startDrill('targets'));
  $('stop-drill').addEventListener('click',() => { drill = null; renderDrill(); status('点按测量已停止，恢复正常输入。'); });
  $('export').addEventListener('click',exportReport);
  $('layout-id').textContent = layout.layoutId;
  for (const source of layout.sources || []) $('sources').append(node('li',typeof source === 'string' ? source : `${source.path} · ${source.sha256 || ''}`));
  updateEnvironment();
  window.addEventListener('resize',updateEnvironment);
  await client.connect(layout.layoutId,$('code-mode').value);
  $('engine-scope').textContent = typeof client.info.scope === 'string' ? client.info.scope : '独立 Go 会话 · 共享源生成的三种码制索引';
  status('已就绪。点击编码键，或聚焦键盘后使用 ANSI 键盘；候选选择后直接写入本页文本。');
}
init().catch(error => {
  $('load-error').hidden = false;
  $('load-error').textContent = error.message;
  $('connection').textContent = '未连接';
  status('初始化未完成，当前页面不能输入。');
});
