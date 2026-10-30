import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {actionFromKeyboard,protocolAction,virtualKeyAction,createLiveClient,samePointerRelease,editText,INPUT_POLICY} from './input.mjs';

test('generated 134-key layered board reaches every printable ASCII and each of its 75 semantic IDs',() => {
  const layout = JSON.parse(readFileSync(new URL('./data/physical-layout.json',import.meta.url),'utf8'));
  const characters = new Set(), ids=[];
  assert.equal(layout.formatVersion,4);
  assert.equal(layout.keys.length,134);
  for (const key of layout.keys) {
    for (const shifted of [false,true]) {
      const action = virtualKeyAction(key,shifted,true).action;
      if (action?.ascii && /^[\x20-\x7e]$/.test(action.ascii)) characters.add(action.ascii);
      if (action?.type === 'confirm' && action.key === 'Space') characters.add(' ');
    }
    for (const [field,shifted] of [['baseYinyuanIds',false],['shiftYinyuanIds',true]]) for (const id of key[field] || []) {
      ids.push(id);
      assert.equal(virtualKeyAction(key,shifted).action.type,'input',id);
    }
    if (key.zone !== 'main' && key.action.ascii) assert.equal(key.action.type,'literal');
  }
  assert.deepEqual([...characters].sort(),Array.from({length:95},(_,i) => String.fromCharCode(32+i)).sort());
  assert.equal(ids.length,75);
  assert.equal(new Set(ids).size,75);
  for (const id of ['M25','M26','M27',...Array.from({length:15},(_,i)=>`R${String(i+4).padStart(2,'0')}`)]) assert.ok(ids.includes(id),id);
});

test('ANSI letters, digits and symbols all defer classification to the engine',() => {
  for (const key of ['a','A','N','n','[',']',"'"]) {
    assert.deepEqual(actionFromKeyboard({key,code:'KeyA'}),{type:'input',ascii:key});
  }
  for (let ordinal = 1; ordinal <= 9; ordinal++) {
    for (const shiftKey of [false,true]) {
      const key = shiftKey ? '!@#$%^&*('[ordinal-1] : String(ordinal);
      assert.deepEqual(actionFromKeyboard({key,code:`Digit${ordinal}`,shiftKey}),{type:'input',ascii:key});
      assert.deepEqual(actionFromKeyboard({key:String(ordinal),code:`Numpad${ordinal}`,shiftKey}),{type:'literal',ascii:String(ordinal)});
    }
  }
  assert.deepEqual(actionFromKeyboard({key:'0',code:'Digit0'}),{type:'input',ascii:'0'});
  assert.deepEqual(actionFromKeyboard({key:')',code:'Digit0',shiftKey:true}),{type:'input',ascii:')'});
  assert.deepEqual(actionFromKeyboard({key:'-',code:'Minus'}),{type:'input',ascii:'-'});
  assert.deepEqual(actionFromKeyboard({key:'=',code:'Equal'}),{type:'input',ascii:'='});
  assert.deepEqual(actionFromKeyboard({key:'PageUp',code:'PageUp'}),{type:'page',delta:-1});
  assert.deepEqual(actionFromKeyboard({key:'PageDown',code:'PageDown'}),{type:'page',delta:1});
  assert.deepEqual(actionFromKeyboard({key:'-',code:'NumpadSubtract'}),{type:'literal',ascii:'-'});
  assert.deepEqual(actionFromKeyboard({key:'_',code:'Minus',shiftKey:true}),{type:'input',ascii:'_'});
  assert.equal(actionFromKeyboard({key:'a',ctrlKey:true}),null);
  assert.equal(actionFromKeyboard({key:'a',altKey:true}),null);
  assert.equal(actionFromKeyboard({key:'a',isComposing:true}),null);
  assert.equal(actionFromKeyboard({key:'a',repeat:true}),null);
  assert.equal(actionFromKeyboard({key:'1',code:'Digit1',ctrlKey:true}),null);
  assert.equal(actionFromKeyboard({key:'1',code:'Digit1',altKey:true}),null);
  assert.equal(actionFromKeyboard({key:'1',code:'Digit1',metaKey:true}),null);
  assert.equal(actionFromKeyboard({key:'1',code:'Digit1',isComposing:true}),null);
  assert.equal(actionFromKeyboard({key:'1',code:'Digit1',repeat:true}),null);
});

test('main-row and virtual digit positions send input regardless of stale visible candidate state',() => {
  const state = {candidates:Array.from({length:9},(_,i) => ({id:`candidate-${i+1}`}))};
  for (let ordinal = 1; ordinal <= 9; ordinal++) {
    const action = actionFromKeyboard({key:String(ordinal),code:`Digit${ordinal}`});
    const expected = {type:'input',code:String(ordinal)};
    assert.deepEqual(protocolAction(action,state),expected);
    assert.deepEqual(protocolAction(action,{candidates:[]}),expected);
    assert.deepEqual(protocolAction(action,{raw_input:'unknown',candidates:[]}),expected);
    assert.deepEqual(protocolAction({type:'select',ordinal},state),expected);
  }
  assert.deepEqual(protocolAction(actionFromKeyboard({key:'9',code:'Digit9'}),{candidates:[{id:'only'}]}),{type:'input',code:'9'});
  for (const ordinal of [0,10,1.5,'1',null]) assert.throws(() => protocolAction({type:'select',ordinal},state));
});

test('every printable ASCII character takes the engine path, never local punctuation edits',() => {
  for (let code = 33; code <= 126; code++) {
    const key = String.fromCharCode(code);
    const action = actionFromKeyboard({key,shiftKey:true});
    assert.deepEqual(action,{type:'input',ascii:key});
    assert.deepEqual(protocolAction(action,{candidates:[{id:'first'}]}),{type:'input',code:key});
    assert.equal(editText('你好',1,1,key),null);
  }
});

test('virtual Shift uses only explicit upper actions including letter carriers',() => {
  const shift = {action:{type:'shift'}};
  assert.deepEqual(virtualKeyAction(shift,false),{action:null,armed:true});
  assert.deepEqual(virtualKeyAction(shift,true),{action:null,armed:false});
  const digit = {action:{type:'select',ordinal:1},shiftAction:{type:'input',ascii:'!'}};
  assert.deepEqual(virtualKeyAction(digit,true),{action:{type:'input',ascii:'!'},armed:false});
  assert.deepEqual(virtualKeyAction(digit,false),{action:{type:'select',ordinal:1},armed:false});
  for (const ascii of ['n','N']) assert.deepEqual(virtualKeyAction({action:{type:'input',ascii}},true),{action:{type:'input',ascii},armed:false});
  const codingSymbol = {action:{type:'input',ascii:'['},shiftAction:{type:'input',ascii:'{'}};
  assert.deepEqual(virtualKeyAction(codingSymbol,true),{action:{type:'input',ascii:'{'},armed:false});
  const letter = {action:{type:'input',ascii:'A'},shiftAction:{type:'input',ascii:'Q'}};
  assert.deepEqual(virtualKeyAction(letter,true),{action:{type:'input',ascii:'Q'},armed:false});
  assert.deepEqual(virtualKeyAction({action:{type:'clear'}},true),{action:{type:'clear'},armed:false});
  assert.deepEqual(virtualKeyAction({action:{type:'page',delta:1}},true),{action:{type:'page',delta:1},armed:true});
});

test('numeric side keys bypass composition and side edit 5 is a no-op',() => {
  for (const ascii of '0123456789.+-*/') {
    const action = actionFromKeyboard({key:ascii,code:'Numpad1'});
    assert.deepEqual(protocolAction(action,{raw_input:'ni',candidates:[{id:'first'}]}),{type:'literal',code:ascii});
  }
  for (const key of ['Home','End','PageUp','PageDown','Insert','Delete','ArrowLeft','ArrowRight','ArrowUp','ArrowDown']) {
    assert.deepEqual(actionFromKeyboard({key,code:'Numpad1'}),{type:'local',key});
  }
  assert.deepEqual(actionFromKeyboard({key:'Clear',code:'Numpad5'}),{type:'noop'});
  const five = {action:{type:'literal',ascii:'5'},editAction:{type:'noop'}};
  assert.deepEqual(virtualKeyAction(five,true,false),{action:{type:'noop'},armed:true});
  assert.deepEqual(virtualKeyAction(five,true,true),{action:{type:'literal',ascii:'5'},armed:false});
  assert.deepEqual(virtualKeyAction({action:{type:'literal',ascii:'/'},zone:'left'},true,false),{action:{type:'literal',ascii:'/'},armed:false});
});

test('language toggle couples punctuation and English Space never selects paused Chinese',() => {
  const state = {raw_input:'ni',candidates:[{id:'first'}]};
  assert.deepEqual(protocolAction({type:'toggle-language'},state,{input:'chinese',punctuation:'english'}),{type:'setModes',inputMode:'english',punctuationMode:'english'});
  assert.deepEqual(protocolAction({type:'toggle-punctuation'},state,{input:'english',punctuation:'english'}),{type:'setModes',punctuationMode:'chinese'});
  assert.deepEqual(protocolAction({type:'confirm',key:'Space'},state,{input:'english'}),{type:'literal',code:' '});
  assert.deepEqual(protocolAction({type:'confirm',key:'Enter'},state,{input:'english'}),{type:'literal',code:'\n'});
  assert.deepEqual(protocolAction({type:'confirm',key:'Space'},state,{input:'chinese'}),{type:'select',candidateId:'first'});
  assert.deepEqual(protocolAction({type:'setModes',inputMode:'english',punctuationMode:'chinese'},state),{type:'setModes',inputMode:'english',punctuationMode:'chinese'});
  for (const action of [{type:'setModes'},{type:'setModes',inputMode:'ascii'},{type:'setModes',punctuationMode:''}]) assert.throws(() => protocolAction(action,state));
  for (const ascii of [' ','\n','\t']) assert.deepEqual(protocolAction({type:'literal',ascii},state),{type:'literal',code:ascii});
  for (const ascii of ['','ab','你','\r','\x00','\x7f','a\n','\n\n']) assert.throws(() => protocolAction({type:'literal',ascii},state));
});

test('pointer ASCII and ANSI ASCII produce identical engine events; reserved IDs cannot be sent',() => {
  const state = {candidates:[{id:'candidate-1',text:'你'}]};
  assert.deepEqual(protocolAction({type:'input',ascii:'N'},state),protocolAction(actionFromKeyboard({key:'N',code:'KeyN',shiftKey:true}),state));
  assert.deepEqual(protocolAction({type:'select',candidateId:'candidate-1'},state),{type:'select',candidateId:'candidate-1'});
  assert.deepEqual(protocolAction({type:'input',ascii:'1'},state),{type:'input',code:'1'});
  assert.deepEqual(protocolAction({type:'select',ordinal:2},state),{type:'input',code:'2'});
  assert.equal(protocolAction({type:'select',candidateId:'stale'},state),null);
  assert.equal(protocolAction({type:'confirm'},{}),null);
  assert.throws(() => protocolAction({type:'input',yinyuanId:'M25',ascii:'M25'},state));
});

test('invalid ASCII rejects whole tokens and non-ASCII instead of inferring an音元',() => {
  for (const ascii of ['M25','你','',null,'\n',' ','a\n']) assert.throws(() => protocolAction({type:'input',ascii},{}));
  assert.equal(protocolAction({type:'page',delta:1},{has_next:false}),null);
  assert.deepEqual(protocolAction({type:'page',delta:-1},{has_previous:true}),{type:'page',delta:-1});
});

test('release outside, cancelled drag return and another pointer never activate',() => {
  const rect = {left:10,top:10,right:50,bottom:60};
  const active = {pointerId:1,left:false};
  assert.equal(samePointerRelease(active,{pointerId:1,clientX:20,clientY:20},rect),true);
  assert.equal(samePointerRelease(active,{pointerId:1,clientX:50,clientY:20},rect),false);
  assert.equal(samePointerRelease({...active,left:true},{pointerId:1,clientX:20,clientY:20},rect),false);
  assert.equal(samePointerRelease(active,{pointerId:2,clientX:20,clientY:20},rect),false);
});

test('queued input derives each revision from prior result, then blur clears pending input',async () => {
  const requests = [], results = [];
  let revision = 0, raw = '', count = 0;
  const fetcher = async (url,options) => {
    const body = options.body ? JSON.parse(options.body) : null;
    requests.push({url,body,headers:options.headers});
    if (url.endsWith('/info')) return response({layoutId:'layout-1',token:'token',inputPolicy:INPUT_POLICY});
    if (url.endsWith('/session')) return response({ok:true,sessionId:'session-1',revision,state:{}});
    assert.equal(body.baseRevision,revision);
    assert.equal(options.headers['X-Yime-Lab-Token'],'token');
    await new Promise(resolve => setTimeout(resolve,2));
    if (body.type === 'input') raw += body.code;
    if (body.type === 'clear') raw = '';
    revision++;
    return response({ok:true,sessionId:'session-1',revision,state:{raw_input:raw}});
  };
  const client = createLiveClient({fetcher,idFactory:() => `event-${++count}`,onResult:result => results.push(result)});
  await client.connect('layout-1');
  await Promise.all([client.dispatch({type:'input',ascii:'n'}),client.dispatch({type:'input',ascii:'I'}),client.dispatch({type:'clear'})]);
  assert.deepEqual(requests.filter(r => r.body?.eventId).map(r => r.body.baseRevision),[0,1,2]);
  assert.equal(client.snapshot.state.raw_input,'');
  assert.equal(results.length,4);
});

test('mode switch closes old session before creating a new one',async () => {
  const requests = [];
  const client = createLiveClient({fetcher:async (url,options) => {
    const body = options.body ? JSON.parse(options.body) : null;
    requests.push(body);
    if (url.endsWith('/info')) return response({layoutId:'layout',token:'t',inputPolicy:INPUT_POLICY});
    return response({ok:true,sessionId:'s',revision:0,state:{raw_input:'n'}});
  },idFactory:() => 'id'});
  await client.connect('layout');
  await client.changeMode('full');
  assert.equal(requests[2].type,'close');
  assert.equal(requests[3].mode,'full');
});

test('queued language toggles read authoritative prior response and couple punctuation',async () => {
  let revision = 0, modes = {input:'chinese',punctuation:'chinese'};
  const events = [];
  const client = createLiveClient({fetcher:async (url,options) => {
    if (url.endsWith('/info')) return response({layoutId:'layout',token:'t',inputPolicy:INPUT_POLICY});
    if (url.endsWith('/event')) {
      const event = JSON.parse(options.body);
      events.push(event);
      assert.equal(event.baseRevision,revision++);
      if (event.inputMode) modes = {...modes,input:event.inputMode};
      if (event.punctuationMode) modes = {...modes,punctuation:event.punctuationMode};
    }
    return response({ok:true,sessionId:'s',revision,state:{raw_input:'n'},modes});
  },idFactory:() => 'e'+revision});
  await client.connect('layout');
  await Promise.all([client.dispatch({type:'toggle-language'}),client.dispatch({type:'toggle-language'})]);
  assert.deepEqual(events.map(e => e.inputMode),['english','chinese']);
  assert.deepEqual(client.snapshot.modes,{input:'chinese',punctuation:'chinese'});
  assert.equal(client.snapshot.state.raw_input,'n');
});

test('code-mode replacement restores independent input and punctuation modes on the new session',async () => {
  const events=[];
  const modes={input:'english',punctuation:'chinese'};
  let session=0;
  const client=createLiveClient({fetcher:async (url,options)=>{
    if(url.endsWith('/info'))return response({layoutId:'layout',token:'t',inputPolicy:INPUT_POLICY});
    const body=JSON.parse(options.body);events.push(body);
    if(url.endsWith('/session'))session++;
    return response({ok:true,sessionId:'s'+session,revision:0,state:{},modes:session===1?modes:{input:'chinese',punctuation:'english'}});
  },idFactory:()=> 'event'});
  await client.connect('layout');await client.changeMode('full');
  assert.equal(events[1].type,'close');
  assert.equal(events[2].mode,'full');
  assert.deepEqual(events[3],{sessionId:'s2',eventId:'event',baseRevision:0,type:'setModes',inputMode:'english',punctuationMode:'chinese'});
});

test('network uncertainty blocks later events instead of replaying potential commits',async () => {
  let posts = 0;
  const client = createLiveClient({fetcher:async (url) => {
    if (url.endsWith('/info')) return response({layoutId:'layout',token:'t',inputPolicy:INPUT_POLICY});
    if (url.endsWith('/session')) return response({sessionId:'s',revision:0,state:{candidates:[{id:'c',text:'你'}]}});
    posts++;
    throw new Error('network lost');
  },idFactory:() => 'id'});
  await client.connect('layout');
  await assert.rejects(client.dispatch({type:'select',ordinal:1}),/network lost/);
  await assert.rejects(client.dispatch({type:'input',ascii:'n'}),/未连接/);
  assert.equal(posts,1);
});

test('stale input policy blocks session creation and asks for a service restart',async () => {
  for (const inputPolicy of [undefined,'candidate-only-v0']) {
    const requests = [];
    const client = createLiveClient({fetcher:async url => {
      requests.push(url);
      return response({layoutId:'layout',token:'t',inputPolicy});
    }});
    await assert.rejects(client.connect('layout'),/重启更新后的实验服务/);
    assert.equal(client.connected,false);
    assert.deepEqual(requests,['./api/info']);
  }
});

test('local text edits preserve graphemes and only change the selected page range',() => {
  assert.deepEqual(editText('你好',1,2,'Tab'),{value:'你\t',start:2,end:2});
  assert.deepEqual(editText('你好',1,1,'ArrowRight'),{value:'你好',start:2,end:2});
  assert.deepEqual(editText('𠀀好',2,2,'Backspace'),{value:'好',start:0,end:0});
  assert.deepEqual(editText('a\u0301好',0,0,'Delete'),{value:'好',start:0,end:0});
  assert.deepEqual(editText('\na',0,0,'Home'),{value:'\na',start:0,end:0});
  assert.equal(editText('你好',0,0,'Win'),null);
  assert.deepEqual(editText('你好',1,1,'PageUp'),{value:'你好',start:0,end:0});
  assert.deepEqual(editText('你好',1,1,'PageDown'),{value:'你好',start:2,end:2});
});

test('confirmed composition rejection keeps queued Backspace, selection and Clear usable without replay',async () => {
  for (const status of [400,409]) {
    let raw = 'n'.repeat(128), revision = 7, ids = 0;
    const events = [], rendered = [];
    const modes = {input:'chinese',punctuation:'chinese'};
    const state = () => ({raw_input:raw,candidates:[{id:'candidate-1',text:'你'}]});
    const client = createLiveClient({idFactory:() => `event-${++ids}`,onResult:r => rendered.push(r),fetcher:async (url,options) => {
      if (url.endsWith('/info')) return response({layoutId:'layout',token:'t',inputPolicy:INPUT_POLICY});
      if (url.endsWith('/session')) return response({ok:true,sessionId:'s',revision:status === 400 ? revision : 0,state:state(),modes});
      const event = JSON.parse(options.body); events.push(event);
      if (event.type === 'input') return response({ok:false,error:status === 400 ? 'composition limit reached' : 'stale revision',sessionId:'s',revision,state:state(),modes},status);
      assert.equal(event.baseRevision,revision);
      if (event.type === 'backspace') raw = raw.slice(0,-1);
      if (event.type === 'clear' || event.type === 'select') raw = '';
      return response({ok:true,sessionId:'s',revision:++revision,state:state(),modes,commit:event.type === 'select' ? '你' : undefined});
    }});
    await client.connect('layout');
    const rejected = assert.rejects(client.dispatch({type:'input',ascii:'n'}),/composition limit|stale revision/);
    const backspace = client.dispatch({type:'backspace'});
    await rejected;
    await backspace;
    assert.equal(client.connected,true);
    assert.equal(client.snapshot.state.raw_input.length,127);
    assert.equal(rendered[1].state.raw_input.length,128); // synchronized rejection is rendered
    assert.deepEqual(client.snapshot.modes,modes);
    assert.equal((await client.dispatch({type:'select',candidateId:'candidate-1'})).commit,'你');
    await assert.rejects(client.dispatch({type:'input',ascii:'n'}));
    assert.equal(rendered.filter(r => r.commit).length,1); // resync must not re-emit a previous commit
    await client.dispatch({type:'clear'});
    assert.equal(client.snapshot.state.raw_input,'');
    assert.deepEqual(events.map(e => e.type),['input','backspace','select','input','clear']);
    assert.equal(new Set(events.map(e => e.eventId)).size,5);
  }
});

test('rejected input resynchronizes pending dots before backspace and flush without replay',async () => {
  const modes = {input:'chinese',punctuation:'chinese'};
  const state = {raw_input:'',candidates:[]};
  let revision=4, pending=2, ids=0;
  const events=[], rendered=[];
  const client=createLiveClient({idFactory:()=>`dots-${++ids}`,onResult:r=>rendered.push(r),fetcher:async(url,options)=>{
    if (url.endsWith('/info')) return response({layoutId:'layout',token:'t',inputPolicy:INPUT_POLICY});
    if (url.endsWith('/session')) return response({ok:true,sessionId:'s',revision:0,state,modes});
    const event=JSON.parse(options.body); events.push(event);
    if (event.type==='input') return response({ok:false,error:'stale revision',sessionId:'s',revision,state,modes,pendingMiddleDots:pending},409);
    assert.equal(event.baseRevision,revision);
    let commit='';
    if (event.type==='backspace') pending--;
    if (event.type==='flushSymbols') { commit='·'.repeat(pending); pending=0; }
    return response({ok:true,sessionId:'s',revision:++revision,state,modes,pendingMiddleDots:pending,commit});
  }});
  await client.connect('layout');
  await assert.rejects(client.dispatch({type:'input',ascii:'a'}),/stale revision/);
  assert.equal(client.snapshot.pendingMiddleDots,2);
  await client.dispatch({type:'backspace'});
  assert.equal(client.snapshot.pendingMiddleDots,1);
  assert.equal((await client.dispatch({type:'flushSymbols'})).commit,'·');
  assert.equal(client.snapshot.pendingMiddleDots,0);
  assert.deepEqual(events.map(e=>e.type),['input','backspace','flushSymbols']);
  assert.equal(rendered.filter(r=>r.commit).length,1);
});

test('terminal and untrusted API failures remain disconnected without replaying input',async () => {
  const valid = {ok:false,error:'rejected',sessionId:'s',revision:0,state:{raw_input:'n'},modes:{input:'chinese',punctuation:'english'}};
  const failures = [
    [400,{...valid,sessionId:'other'}], [400,{...valid,revision:-1}],
    [400,{...valid,state:null}], [400,{...valid,modes:null}],
    ...[null,1,'candidate',{}, {id:'c'}, {id:1,text:'你'}, {id:'c',text:null}]
      .map(candidate => [400,{...valid,state:{raw_input:'n',candidates:[candidate]}}]),
    [400,{...valid,commit:'你'}], [400,{ok:false,error:'bad request'}],
    [403,valid], [404,valid], [410,valid], [429,valid], [500,valid],
    [400,null], [400,{...valid,ok:true}],
  ];
  for (const [status,body] of failures) {
    let posts = 0;
    const client = createLiveClient({fetcher:async url => {
      if (url.endsWith('/info')) return response({layoutId:'layout',token:'t',inputPolicy:INPUT_POLICY});
      if (url.endsWith('/session')) return response({sessionId:'s',revision:0,state:{raw_input:'n'}});
      posts++;
      return response(body,status);
    }});
    await client.connect('layout');
    await assert.rejects(client.dispatch({type:'input',ascii:'n'}));
    assert.equal(client.connected,false);
    await assert.rejects(client.dispatch({type:'clear'}),/未连接/);
    assert.equal(posts,1);
  }
});

test('ellipsis choices survive a stale resync and remain selectable in English',async () => {
  const modes={input:'english',punctuation:'english'};
  const choices=[{id:'ellipsis:6:2026',text:'……'},{id:'ellipsis:6:22ef',text:'⋯⋯'}];
  let ids=0;
  const client=createLiveClient({idFactory:()=>`choice-${++ids}`,fetcher:async(url,options)=>{
    if(url.endsWith('/info'))return response({layoutId:'layout',token:'t',inputPolicy:INPUT_POLICY});
    if(url.endsWith('/session'))return response({ok:true,sessionId:'s',revision:0,state:{raw_input:'p',candidates:[]},modes});
    const event=JSON.parse(options.body);
    if(event.type==='input')return response({ok:false,error:'stale revision',sessionId:'s',revision:6,state:{raw_input:'p',candidates:choices},modes,pendingMiddleDots:6,symbolChoice:true},409);
    assert.equal(event.type,'select');assert.equal(event.baseRevision,6);assert.equal(event.candidateId,choices[1].id);
    return response({ok:true,sessionId:'s',revision:7,state:{raw_input:'p',candidates:[]},modes,commit:'⋯⋯'});
  }});
  await client.connect('layout');
  await assert.rejects(client.dispatch({type:'input',ascii:'a'}),/stale revision/);
  assert.equal(client.snapshot.symbolChoice,true);assert.equal(client.snapshot.pendingMiddleDots,6);
  assert.equal((await client.dispatch({type:'select',candidateId:choices[1].id})).commit,'⋯⋯');
  assert.equal(client.snapshot.state.raw_input,'p');assert.ok(!client.snapshot.symbolChoice);
});

function response(value,status=200) { return {ok:status>=200 && status<300,status,json:async () => value}; }
