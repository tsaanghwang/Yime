import {viewKey,useEnglishLayout} from './keyboard-layout.mjs';
import {actionFromKeyboard,createLiveClient,editText,virtualKeyAction,DEFAULT_MODES} from './input.mjs';
import {percentile,keyShape,keyContainsPoint} from './geometry.mjs';

const $ = id => document.getElementById(id);
const node = (tag,value,className) => {
  const element = document.createElement(tag);
  element.textContent = value;
  if (className) element.className = className;
  return element;
};
let layout, client, active = null, trace = [], touches = [], latencies = [], drill = null;
let shiftArmed = false, layoutPreference = 'original', literalEntries = false;
const layoutLatencies = [];
let lastLiteral = null;
try { if (localStorage.getItem('yime-lab-english-layout') === 'english') layoutPreference = 'english'; } catch {}
const englishLayout = () => useEnglishLayout(currentModes().input,layoutPreference);
const displayedKey = key => viewKey(key,englishLayout());
function toggleLayout() {
  if (currentModes().input !== 'english') { status('布局开关用于英文输入。'); return; }
  const started = performance.now();
  cancelPointer('layout-change'); cancelShifts('layout-change');
  drill = null;
  layoutPreference = layoutPreference === 'english' ? 'original' : 'english';
  try { localStorage.setItem('yime-lab-english-layout',layoutPreference); } catch {}
  refreshKeyboard(); renderDrill();
  status(`英文布局：${englishLayout() ? '标准英文' : '原盘面'}。`);
  requestAnimationFrame(() => {
    layoutLatencies.push(performance.now()-started);
    if (layoutLatencies.length > 1000) layoutLatencies.shift();
    $('layout-latency').textContent = `布局切换 → 下一帧 p50 ${percentile(layoutLatencies,.5).toFixed(1)} / p95 ${percentile(layoutLatencies,.95).toFixed(1)} ms（浏览器代理指标）`;
  });
}
const shiftPointers = new Map(), ansiShift = new Set(), numLocks = {left:true,right:true};
let overwrite = false;
const keyButtons = new Map(), drills = [];
const status = message => { $('status').textContent = message; };
const focusBoard = () => $('keyboard').focus({preventScroll:true});
const currentState = () => client?.snapshot?.state || {raw_input:'',candidates:[],page_number:0};
const currentModes = () => client?.snapshot?.modes || DEFAULT_MODES;
const effectiveShift = () => shiftArmed || ansiShift.size > 0 || [...shiftPointers.values()].some(p => !p.left);

function appendCommit(value, event) {
  const surface = $('committed');
  const symbol = event?.type === 'symbol' ? event.code : null;
  // Consolidate only consecutive explicit symbol commits at the same cursor.
  // Editing, another action, or moving the cursor breaks the run.
  if (symbol && ['—','·'].includes(symbol) && lastLiteral?.symbol === symbol &&
      surface.selectionStart === surface.selectionEnd && surface.selectionStart === lastLiteral.end) {
    const count = lastLiteral.count + 1;
    const width = symbol === '—' ? 2 : 3;
    if (count === width && surface.value.slice(surface.selectionStart-width+1,surface.selectionStart) === symbol.repeat(width-1)) {
      surface.setSelectionRange(surface.selectionStart-width+1,surface.selectionEnd);
      value = symbol === '—' ? '——' : '…';
      lastLiteral = null;
    } else lastLiteral = {symbol,count,end:surface.selectionStart+value.length};
  } else lastLiteral = symbol && ['—','·'].includes(symbol) ? {symbol,count:1,end:surface.selectionStart+value.length} : null;
  if (overwrite && !currentState().raw_input && surface.selectionStart === surface.selectionEnd) {
    const length = Array.from(value).length;
    const tail = Array.from(new Intl.Segmenter(undefined,{granularity:'grapheme'}).segment(surface.value.slice(surface.selectionEnd))).slice(0,length).map(part => part.segment).join('');
    surface.setSelectionRange(surface.selectionStart,surface.selectionEnd+tail.length);
  }
  surface.setRangeText(value,surface.selectionStart,surface.selectionEnd,'end');
  surface.dispatchEvent(new Event('input',{bubbles:true}));
}

function render(result, event) {
  if (result.commit) appendCommit(result.commit,event);
  const state = result.state, candidates = state.candidates || [];
  const paused = currentModes().input === 'english';
  $('code').textContent = state.raw_input || '—';
  $('composition').textContent = state.raw_input ? paused ? '中文组合已暂停并保留；当前英文字符直接写入正文。切回中文可继续。' : '正在组合；候选来自当前码制的 Go 引擎。' : paused ? '英文直输：Layout 切换原盘面／标准英文，选择保持至再次切换。' : '点按编码键，或在这里使用 ANSI 键盘。';
  $('candidates').replaceChildren();
  if (!candidates.length) $('candidates').append(node('p',state.raw_input ? '当前编码暂无候选，可继续输入、退格或取消。' : '候选将显示在这里。','hint'));
  candidates.forEach((candidate,index) => {
    const button = document.createElement('button');
    button.className = 'candidate';
    button.disabled = paused;
    button.dataset.candidateId = candidate.id;
    button.append(node('span',String(index+1),'ordinal'),node('span',candidate.text));
    button.title = `候选 ${index+1} · ANSI 直接按 ${index+1}`;
    button.addEventListener('click',() => {
      perform({type:'select',candidateId:candidate.id},'candidate');
      focusBoard();
    });
    $('candidates').append(button);
  });
  $('confirm').disabled = paused || !candidates.length;
  $('clear').disabled = !state.raw_input && !shiftArmed;
  $('prev').disabled = paused || !state.has_previous;
  $('next').disabled = paused || !state.has_next;
  $('page-label').textContent = candidates.length ? `第 ${(state.page_number || 0)+1} 页` : '';
  $('connection').textContent = 'Go 引擎已连接 · 仅本页文本';
  $('connection').classList.add('connected');
  $('input-mode').textContent = `输入：${paused ? '英文直输' : '中文编码'}`;
  $('input-mode').setAttribute('aria-pressed',String(paused));
  $('punctuation-mode').textContent = `标点：${currentModes().punctuation === 'chinese' ? '中文' : '英文'}`;
  $('punctuation-mode').setAttribute('aria-pressed',String(currentModes().punctuation === 'chinese'));
  refreshKeyboard();
  if (event) {
    trace.push({event,result});
    if (trace.length > 100) trace.shift();
    $('trace').textContent = JSON.stringify(trace.slice(-2),null,2);
  }
}

function localEdit(key) {
  if (currentState().raw_input && currentModes().input !== 'english') {
    status('请先选词或取消当前组合，再编辑已确认文本。');
    return;
  }
  if (key === 'Insert') { overwrite = !overwrite; status(`本页文本${overwrite ? '覆盖' : '插入'}模式；不改变系统键盘状态。`); return; }
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
  if (action?.type === 'toggle-layout') { toggleLayout(); return Promise.resolve(); }
  if (action?.type !== 'symbol') lastLiteral = null;
  if ((action?.type === 'clear' && source !== 'drill') || ['toggle-language','toggle-punctuation','setModes'].includes(action?.type)) {
    cancelPointer('input-boundary');
    cancelShifts('input-boundary');
  }
  // Serialize the entire action, including local text edits, so a quick sequence
  // cannot inspect composition state before the preceding input response arrives.
  actions = actions.then(() => performOne(action,source)).catch(error => status(`操作未完成：${error.message}`));
  return actions;
}
async function performOne(action,source) {
  if (action?.type !== 'symbol') lastLiteral = null;
  if (!action || action.type === 'disabled') return;
  if (action.type === 'noop') { status('编辑模式下 5 不执行动作。'); return; }
  if (action.type === 'unsupported') {
    status(`${action.label || '此键'} 仅保留实体键位；没有发送系统快捷键。`);
    return;
  }
  if (action.type === 'local') { localEdit(action.key); return; }
  if (!client.connected) { status('引擎未连接，请使用项目的本地服务并刷新页面。'); return; }
  if (action.type === 'confirm' && !currentState().raw_input && currentModes().input !== 'english') { localEdit(action.key || 'Space'); return; }
  if (action.type === 'backspace' && (!currentState().raw_input || currentModes().input === 'english')) { localEdit('Backspace'); return; }
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
    if (client.connected) {
      $('connection').textContent = 'Go 引擎已连接 · 本次操作被拒绝，可继续退格或清空';
    } else {
      $('connection').textContent = '连接中断 · 请刷新重新连接';
    }
    $('connection').classList.toggle('connected',client.connected);
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
function recordKey(key,pointerType,pointer,cancelled=false,reason=null,layer=null) {
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
  const shifted = layer?.shifted ?? effectiveShift(), numeric = layer?.numeric ?? (numLocks[key.zone] ?? true);
  const resolved = !cancelled && !running ? virtualKeyAction(key,shifted,numeric,literalEntries) : {action:key.action,armed:shiftArmed};
  touches.push({physicalKeyId:key.id,yinyuanIds:key.yinyuanIds,action:resolved.action,baseAction:key.action,shiftArmed:shifted,zone:key.zone,numeric,pointerType,pointer,cancelled,reason,
    drillKind:running ? drill.kind : null,drillResult:outcome,intended,timeMs:Math.round(performance.now())});
  if (touches.length > 1000) touches.shift();
  renderDrill();
  if (running && !drillActive()) refreshKeyboard();
  // Coverage drills test geometry without altering the local test document.
  if (!cancelled && !running) {
    if (key.action.type === 'toggle-number') {
      numLocks[key.zone] = !numeric;
      refreshKeyboard();
      status(`${key.zone === 'left' ? '左' : '右'}侧数字区：${numLocks[key.zone] ? '数字直输' : '本页编辑'}。`);
    } else if (key.action.type === 'shift') {
      setVirtualShift(!shiftArmed);
      status(shiftArmed ? '一次 Shift 已启用；上档输出严格遵循键帽。' : '一次 Shift 已关闭。');
    } else {
      if (['input','literal','select','symbol'].includes(resolved.action?.type)) {
        for (const press of shiftPointers.values()) press.used = true;
        setVirtualShift(false);
      }
      if (resolved.action) perform(resolved.action);
    }
  }
}
function cancelPointer(reason,event=null) {
  if (!active) return;
  const previous = active;
  active = null;
  previous.button.classList.remove('pressed');
  const rect = previous.button.getBoundingClientRect();
  recordKey(previous.key,previous.pointerType,{down:previous.down,...(event ? {up:pointerSample(event,rect)} : {}),holdMs:Math.round(performance.now()-previous.startedAt)},true,reason);
  if (!drillActive() && reason !== 'drill-start') setVirtualShift(false);
  status('点按已取消，没有发送按键动作。');
}

function cancelShifts(reason) {
  for (const press of shiftPointers.values()) {
    press.button.classList.remove('pressed');
    touches.push({physicalKeyId:press.key.id,action:{type:'shift'},cancelled:true,reason,pointerType:press.pointerType});
  }
  shiftPointers.clear();
  ansiShift.clear();
  setVirtualShift(false);
  refreshKeyboard();
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
function renderVirtualKey(key,button) {
  button.disabled = Boolean(key.disabled);
  button.dataset.action = key.action.type;
  button.dataset.ascii = key.action.ascii || '';
  button.dataset.layout = englishLayout() ? 'english' : 'original';
  button.dataset.yinyuanIds = (key.yinyuanIds || []).join(',');
  if (key.action.type === 'toggle-layout') {
    button.setAttribute('aria-pressed',String(englishLayout()));
    button.setAttribute('aria-disabled',String(currentModes().input !== 'english' && !drillActive()));
  }
  const shifted = effectiveShift() && key.shiftAction;
  const editing = key.editAction && !numLocks[key.zone];
  const action = virtualKeyAction(key,effectiveShift(),numLocks[key.zone] ?? true,literalEntries).action || key.action;
  const activeLabel = editing ? action.key || '—' : shifted ? action.ascii : null;
  const labels = activeLabel ? Array.from({length:12},(_,i) => i === 4 ? activeLabel : '') : key.displayLabels || key.labels || [];
  const ids = (key.yinyuanIds || []).map(id => (key.disabledYinyuanIds || []).includes(id) ? `${id} 停用` : id).join('，');
  const description = ['input','literal','symbol'].includes(action.type) ? `ASCII ${action.ascii}${action.type === 'literal' ? '（侧区直输）' : ''}${shifted ? '（上档）' : ''}`
    : action.type === 'select' ? `数字 ${action.ordinal}（有候选时选词，否则输入数字）`
    : action.type === 'shift' ? `Shift（${effectiveShift() ? '已启用' : '未启用'}，支持点按或按住）`
    : action.type === 'toggle-number' ? `${key.zone === 'left' ? '左' : '右'} Num Lock（${numLocks[key.zone] ? '数字' : '编辑'}）`
    : action.type === 'toggle-language' ? `中英文切换（当前${currentModes().input === 'chinese' ? '中文' : '英文'}）`
    : action.type === 'toggle-punctuation' ? `标点切换（当前${currentModes().punctuation === 'chinese' ? '中文' : '英文'}）`
    : action.label || action.key || action.type;
  button.setAttribute('aria-label',`${key.id} ${ids || labels.map(legendText).filter(Boolean).join(' ')}，${description}`);
  button.title = `${key.id} · ${description}${ids ? ` · ${ids}` : ''}`;
  button.dataset.activeAscii = action.ascii || (action.type === 'select' ? String(action.ordinal) : '');
  if (key.action.type === 'shift') {
    button.setAttribute('aria-pressed',String(effectiveShift()));
    button.classList.toggle('shift-armed',effectiveShift());
  }
  if (key.action.type === 'toggle-number') button.setAttribute('aria-pressed',String(numLocks[key.zone]));
  if (key.action.type === 'toggle-language') button.setAttribute('aria-pressed',String(currentModes().input === 'english'));
  if (key.action.type === 'toggle-punctuation') button.setAttribute('aria-pressed',String(currentModes().punctuation === 'chinese'));
  // Reuse legend nodes; normal input does not rebuild the key face.
  const signature = JSON.stringify(labels);
  if (button.dataset.legendSignature !== signature) {
    if (!button._legends) {
      button._legends = Array.from({length:12},(_,index) => {
        const span = document.createElement('span'); span.className = `key-legend legend-${index}`;
        button.append(span); return span;
      });
    }
    labels.forEach((label,index) => { button._legends[index].textContent = legendText(label || ''); });
    button.dataset.legendSignature = signature;
  }
  for (const old of button.querySelectorAll('.key-state,.simulation-label,.key-space')) old.remove();
  if (action.type === 'disabled') button.title = `${key.id} · 暂时禁用`;
  if (action.type === 'unsupported') button.append(node('span','仅示意','simulation-label'));
  if (action.type === 'toggle-number') button.append(node('span',numLocks[key.zone] ? '数字' : '编辑','key-state'));
  if (action.type === 'toggle-language') button.append(node('span',currentModes().input === 'chinese' ? '中文' : '英文','key-state'));
  if (action.type === 'toggle-layout') button.append(node('span',englishLayout() ? '英' : '原','key-state'));
  if (action.type === 'toggle-punctuation') button.append(node('span',currentModes().punctuation === 'chinese' ? '中文' : '英文','key-state'));
}
function refreshKeyboard() {
  for (const key of layout?.keys || []) {
    const button = keyButtons.get(key.id);
    if (button) renderVirtualKey(displayedKey(key),button);
  }
  if ($('layout-mode')) $('layout-mode').textContent = `布局：${englishLayout() ? '标准英文' : '原盘面'}`;
  if ($('number-modes')) $('number-modes').textContent = `左数字区：${numLocks.left ? '数字' : '编辑'} · 右数字区：${numLocks.right ? '数字' : '编辑'}`;
}
function setVirtualShift(value) {
  if (shiftArmed === value) return;
  shiftArmed = value;
  $('clear').disabled = !currentState().raw_input && !shiftArmed;
  refreshKeyboard();
}
function buildKeyboard() {
  const board = $('keyboard'), bounds = layout.bounds;
  board.style.setProperty('--keyboard-ratio',`${bounds.width}/${bounds.height}`);
  board.style.setProperty('--keyboard-min-width',`${Math.ceil(bounds.width*54)}px`);
  for (const key of layout.keys) {
    const shape = keyShape(key);
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `physical-key role-${key.action.type}`;
    button.dataset.id = key.id;
    button.dataset.ascii = key.action.ascii || '';
    button.dataset.action = key.action.type;
    button.dataset.yinyuanIds = (key.yinyuanIds || []).join(',');
    button.dataset.zone = key.zone;
    button.style.left = `calc(${100*(key.x+shape.left)/bounds.width}% + 2px)`;
    button.style.top = `calc(${100*(key.y+shape.top)/bounds.height}% + 2px)`;
    button.style.width = `calc(${100*shape.width/bounds.width}% - 4px)`;
    button.style.height = `calc(${100*shape.height/bounds.height}% - 4px)`;
    button.style.clipPath = `polygon(${shape.polygon})`;
    button.style.setProperty('--key-color',key.color || '#deded7');
    button.style.setProperty('--key-text',key.textColor || '#172c30');
    renderVirtualKey(displayedKey(key),button);
    button.addEventListener('pointerdown',event => {
      const current = displayedKey(key);
      if (current.disabled) return;
      if (event.button !== 0 || !keyContainsPoint(key,event,button.getBoundingClientRect())) return;
      const shift = current.action.type === 'shift' && !drillActive();
      if (!shift && active) return;
      event.preventDefault();
      focusBoard();
      const press = {pointerId:event.pointerId,key:current,button,pointerType:event.pointerType,left:false,used:false,startedAt:performance.now(),down:pointerSample(event,button.getBoundingClientRect()),layer:{shifted:effectiveShift(),numeric:numLocks[key.zone] ?? true}};
      if (shift) shiftPointers.set(event.pointerId,press);
      else {
        active = press;
        if (press.layer.shifted) for (const held of shiftPointers.values()) held.used = true;
      }
      button.classList.add('pressed');
      button.setPointerCapture(event.pointerId);
      if (shift) refreshKeyboard();
    });
    button.addEventListener('pointermove',event => {
      const press = shiftPointers.get(event.pointerId) || (active?.pointerId === event.pointerId ? active : null);
      if (!press) return;
      if (!keyContainsPoint(key,event,button.getBoundingClientRect())) {
        press.left = true;
        button.classList.remove('pressed');
        refreshKeyboard();
      }
    });
    button.addEventListener('pointerup',event => {
      const held = shiftPointers.get(event.pointerId);
      if (held) {
        shiftPointers.delete(event.pointerId);
        button.classList.remove('pressed');
        const cancelled = held.left || !keyContainsPoint(key,event,button.getBoundingClientRect());
        if (!held.used || cancelled) recordKey(key,event.pointerType,{down:held.down,up:pointerSample(event,button.getBoundingClientRect())},cancelled,cancelled ? 'left-key' : null);
        else touches.push({physicalKeyId:key.id,action:{type:'shift'},held:true,cancelled:false,pointerType:event.pointerType});
        if (cancelled) setVirtualShift(false);
        refreshKeyboard();
        return;
      }
      if (active?.pointerId !== event.pointerId) return;
      const rect = button.getBoundingClientRect();
      if (active.left || !keyContainsPoint(key,event,rect)) { cancelPointer('left-key',event); return; }
      const completed = active;
      active = null;
      button.classList.remove('pressed');
      recordKey(completed.key,event.pointerType,{down:completed.down,up:pointerSample(event,rect),holdMs:Math.round(performance.now()-completed.startedAt)},false,null,completed.layer);
    });
    for (const type of ['pointercancel','lostpointercapture']) button.addEventListener(type,event => {
      if (shiftPointers.has(event.pointerId)) cancelShifts(type);
      if (active?.pointerId === event.pointerId) cancelPointer(type,event);
    });
    button.addEventListener('click',event => {
      if (event.detail === 0 && !event.pointerType) recordKey(displayedKey(key),'keyboard',null);
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
  if (!action || action.type === 'disabled') return;
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
  cancelShifts('drill-start');
  perform({type:'clear'},'drill');
  const enabled = layout.keys.filter(key => !displayedKey(key).disabled);
  const targets = kind === 'targets'
    ? enabled.map((_,i) => enabled[(i*17+3)%enabled.length].id)
    : enabled.map(key => key.id);
  drill = {kind,targets,seen:[],correct:0,attempts:0,wrong:0,duplicate:0,cancelled:0};
  drills.push(drill);
  renderDrill();
  refreshKeyboard();
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
  const report = {formatVersion:6,displayedLayout:englishLayout() ? 'english' : 'original',englishLayoutPreference:layoutPreference,literalEntries,layoutSwitchHandlerToFrameMs:layoutLatencies,mode:'ascii-physical-keyboard',createdAt:new Date().toISOString(),layoutId:layout.layoutId,touchTemplateId:layout.touchTemplateId,
    inputPolicy:client.info.inputPolicy,inputModes:currentModes(),numberModes:{...numLocks},sources:layout.sources,environment:environment(),disabledYinyuanIds:layout.disabledYinyuanIds,drills,touches,trace,handlerToNextFrameMs:latencies,
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
  if (layout.formatVersion !== 4) throw new Error('页面需要当前134键双布局，请重新生成数据并刷新。');
  buildKeyboard();
  client = createLiveClient({onResult:render});
  $('keyboard').addEventListener('keydown',keyboardInput);
  $('committed').addEventListener('keydown',keyboardInput);
  window.addEventListener('keydown',event => {
    if (event.key === 'Shift' && !event.isComposing && !event.repeat) { ansiShift.add(event.code || 'Shift'); refreshKeyboard(); }
  });
  window.addEventListener('keyup',event => {
    if (event.key === 'Shift') { ansiShift.delete(event.code || 'Shift'); refreshKeyboard(); }
  });
  for (const [id,action] of Object.entries({backspace:{type:'backspace'},clear:{type:'clear'},confirm:{type:'confirm'},prev:{type:'page',delta:-1},next:{type:'page',delta:1}})) {
    $(id).addEventListener('click',() => { perform(action); focusBoard(); });
  }
  $('input-mode').addEventListener('click',() => { perform({type:'toggle-language'}); focusBoard(); });
  $('literal-entries').addEventListener('click',() => {
    cancelPointer('literal-entry-change'); cancelShifts('literal-entry-change');
    literalEntries = !literalEntries;
    $('literal-entries').setAttribute('aria-pressed',String(literalEntries));
    $('literal-entries').textContent = `字面符号入口：${literalEntries ? '开' : '关'}`;
    refreshKeyboard(); focusBoard();
  });
  $('code-mode').addEventListener('change',event => {
    cancelPointer('mode-change');
    cancelShifts('mode-change');
    event.target.disabled = true;
    actions = actions.then(async () => {
      try { await client.changeMode(event.target.value); status('已切换码制，未确认组合已取消。'); }
      catch (error) { status(`切换失败：${error.message}`); }
      finally { event.target.disabled = false; focusBoard(); }
    });
  });
  const cancelComposition = reason => {
    cancelPointer(reason);
    cancelShifts(reason);
    // Always enqueue after pending input, even before its response is visible.
    perform({type:'clear'});
  };
  window.addEventListener('blur',() => cancelComposition('window-blur'));
  document.addEventListener('visibilitychange',() => { if (document.hidden) cancelComposition('page-hidden'); });
  $('drill').addEventListener('click',() => startDrill('coverage'));
  $('target-drill').addEventListener('click',() => startDrill('targets'));
  $('stop-drill').addEventListener('click',() => { drill = null; renderDrill(); status('点按测量已停止，恢复正常输入。'); });
  $('committed').addEventListener('pointerdown',() => { lastLiteral = null; });
  $('export').addEventListener('click',exportReport);
  $('layout-id').textContent = layout.layoutId;
  for (const source of layout.sources || []) $('sources').append(node('li',typeof source === 'string' ? source : `${source.path} · ${source.sha256 || ''}`));
  updateEnvironment();
  window.addEventListener('resize',updateEnvironment);
  await client.connect(layout.layoutId,$('code-mode').value);
  await client.dispatch({type:'setModes',inputMode:'chinese',punctuationMode:'chinese'});
  $('engine-scope').textContent = typeof client.info.scope === 'string' ? client.info.scope : '独立 Go 会话 · 共享源生成的三种码制索引';
  status('已就绪。点击编码键，或聚焦键盘后使用 ANSI 键盘；候选选择后直接写入本页文本。');
}
init().catch(error => {
  $('load-error').hidden = false;
  $('load-error').textContent = error.message;
  $('connection').textContent = '未连接';
  status('初始化未完成，当前页面不能输入。');
});
