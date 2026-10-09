/** Input adapter for the isolated Go engine. No OS keyboard synthesis is used. */
export const CODE_MODES = Object.freeze(['variable', 'full', 'shorthand']);
export const INPUT_POLICY = 'candidate-or-literal-v1';

export function actionFromKeyboard(event) {
  if (event.isComposing || event.ctrlKey || event.altKey || event.metaKey || event.repeat) return null;
  // All printable ASCII uses the same engine decision, including number-pad
  // input. Candidate availability is evaluated after earlier queued events.
  if (typeof event.key === 'string' && /^[\x21-\x7e]$/.test(event.key)) return {type:'input', ascii:event.key};
  const actions = {
    Backspace:{type:'backspace'}, Escape:{type:'clear'},
    Enter:{type:'confirm'}, ' ':{type:'confirm'},
    PageUp:{type:'page',delta:-1}, PageDown:{type:'page',delta:1},
  };
  if (actions[event.key]) return {...actions[event.key]};
  if (['Tab','Delete','Home','End','ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key)) return {type:'local',key:event.key};
  return null;
}

export function protocolAction(action, state) {
  if (action.type === 'input') {
    if (typeof action.ascii !== 'string' || !/^[\x21-\x7e]$/.test(action.ascii)) throw new Error('输入必须是单个非空白 ASCII 字符。');
    return {type:'input',code:action.ascii};
  }
  if (action.type === 'select' && !action.candidateId) {
    if (!Number.isInteger(action.ordinal) || action.ordinal < 1 || action.ordinal > 9) throw new Error('无效的候选序号。');
    return {type:'input',code:String(action.ordinal)};
  }
  if (action.type === 'select' || action.type === 'confirm') {
    const candidates = state.candidates || [];
    const candidate = action.candidateId ? candidates.find(item => item.id === action.candidateId)
      : candidates[(action.ordinal || 1) - 1];
    if (!candidate) return null;
    return {type:'select',candidateId:candidate.id};
  }
  if (action.type === 'page') {
    if (![-1,1].includes(action.delta)) throw new Error('无效的翻页方向。');
    if (!(action.delta < 0 ? state.has_previous : state.has_next)) return null;
    return {type:'page',delta:action.delta};
  }
  if (['backspace','clear'].includes(action.type)) return {type:action.type};
  return null;
}

/** One-shot virtual Shift never changes fixed letter/audio-ID key case. */
export function virtualKeyAction(key, armed=false) {
  if (key.action.type === 'shift') return {action:null,armed:!armed};
  const printable = key.action.type === 'input' || key.action.type === 'select';
  return {
    action:armed && key.shiftAction ? {...key.shiftAction} : {...key.action},
    armed:printable || key.action.type === 'clear' ? false : armed,
  };
}

export function samePointerRelease(active, event, rect) {
  return Boolean(active && active.pointerId === event.pointerId && !active.left
    && event.clientX >= rect.left && event.clientX < rect.right
    && event.clientY >= rect.top && event.clientY < rect.bottom);
}

/** Serialized requests calculate their revision only after earlier input completes. */
export function createLiveClient({fetcher=fetch, idFactory=() => crypto.randomUUID(), onResult=() => {}}={}) {
  let info = null, snapshot = null, queue = Promise.resolve(), broken = false;
  async function request(path, body) {
    const response = await fetcher(path, body ? {
      method:'POST', headers:{'Content-Type':'application/json','X-Yime-Lab-Token':info.token}, body:JSON.stringify(body),
    } : {cache:'no-store'});
    const result = await response.json();
    if (!response.ok || result.ok === false) {
      if (snapshot && result.state && Number.isInteger(result.revision)) snapshot = {...snapshot,state:result.state,revision:result.revision};
      throw new Error(typeof result.error === 'string' ? result.error : `HTTP ${response.status}`);
    }
    return result;
  }
  function enqueue(work) {
    const next = queue.then(work);
    queue = next.catch(() => {});
    return next;
  }
  return Object.freeze({
    get info() { return info; },
    get snapshot() { return snapshot; },
    get connected() { return Boolean(snapshot && !broken); },
    connect(layoutId, mode='variable') {
      return enqueue(async () => {
        info = await request('./api/info');
        if (info.layoutId !== layoutId) throw new Error('页面布局与引擎布局不一致，请重新生成数据并刷新。');
        if (info.inputPolicy !== INPUT_POLICY) throw new Error('输入规则版本不一致，请重启更新后的实验服务并刷新页面。');
        snapshot = await request('./api/session',{layoutId,mode});
        broken = false;
        onResult(snapshot);
        return snapshot;
      });
    },
    changeMode(mode) {
      return enqueue(async () => {
        if (!CODE_MODES.includes(mode) || !snapshot) throw new Error('码制或会话无效。');
        const previous = snapshot;
        await request('./api/event',{sessionId:previous.sessionId,eventId:idFactory(),baseRevision:previous.revision,type:'close'});
        snapshot = null;
        snapshot = await request('./api/session',{layoutId:info.layoutId,mode});
        onResult(snapshot);
        return snapshot;
      });
    },
    dispatch(action) {
      return enqueue(async () => {
        if (!snapshot || broken) throw new Error('引擎未连接。请刷新页面重新建立会话。');
        const payload = protocolAction(action,snapshot.state);
        if (!payload) return null;
        const event = {sessionId:snapshot.sessionId,eventId:idFactory(),baseRevision:snapshot.revision,...payload};
        let result;
        try { result = await request('./api/event',event); }
        catch (error) {
          // An unknown network outcome must not be silently replayed with a new ID.
          broken = true;
          throw error;
        }
        snapshot = result;
        onResult(result,event);
        return result;
      });
    },
    async idle() { await queue; },
  });
}

/** Local text editing is explicit and limited to the page's textarea. */
export function editText(value, start, end, key) {
  const selection = value.slice(0,start), tail = value.slice(end);
  const boundaries = [0,...Array.from(new Intl.Segmenter(undefined,{granularity:'grapheme'}).segment(value),part => part.index+part.segment.length)];
  const previous = boundaries.filter(index => index < start).at(-1) ?? 0;
  const following = boundaries.find(index => index > end) ?? value.length;
  if (key === 'Backspace') return start !== end ? {value:selection+tail,start,end:start}
    : {value:value.slice(0,previous)+tail,start:previous,end:previous};
  if (key === 'Delete') return {value:selection+value.slice(end === start ? following : end),start,end:start};
  let cursor;
  if (key === 'ArrowLeft') cursor = start === end ? previous : start;
  else if (key === 'ArrowRight') cursor = start === end ? following : end;
  else if (key === 'Home') cursor = value.slice(0,start).lastIndexOf('\n')+1;
  else if (key === 'End') { cursor = value.indexOf('\n',end); if (cursor < 0) cursor = value.length; }
  else if (key === 'ArrowUp' || key === 'ArrowDown') {
    const lineStart = value.slice(0,start).lastIndexOf('\n')+1;
    const column = start-lineStart;
    if (key === 'ArrowUp') {
      const previousEnd = Math.max(0,lineStart-1);
      const previousStart = value.slice(0,previousEnd).lastIndexOf('\n')+1;
      cursor = Math.min(previousEnd,previousStart+column);
    } else {
      const lineEnd = value.indexOf('\n',end);
      if (lineEnd < 0) cursor = value.length;
      else { const nextEnd = value.indexOf('\n',lineEnd+1); cursor = Math.min(nextEnd < 0 ? value.length : nextEnd,lineEnd+1+column); }
    }
    cursor = boundaries.filter(index => index <= cursor).at(-1) ?? 0;
  }
  if (cursor !== undefined) return {value,start:cursor,end:cursor};
  // Printable digits/punctuation belong to the engine, never local text edits.
  const inserted = key === 'Enter' ? '\n' : key === 'Tab' ? '\t' : key === 'Space' ? ' ' : null;
  if (inserted !== null) return {value:selection+inserted+tail,start:start+inserted.length,end:start+inserted.length};
  return null;
}
