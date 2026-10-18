import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {actionFromKeyboard,protocolAction,virtualKeyAction,createLiveClient,samePointerRelease,editText,INPUT_POLICY} from './input.mjs';

test('generated 138-key layered board reaches every printable ASCII and each of its 75 semantic IDs',() => {
  const layout = JSON.parse(readFileSync(new URL('./data/physical-layout.json',import.meta.url),'utf8'));
  const characters = new Set(), ids=[];
  assert.equal(layout.formatVersion,3);
  assert.equal(layout.keys.length,138);
  for (const key of layout.keys) {
    for (const shifted of [false,true]) {
      const action = virtualKeyAction(key,shifted,true).action;
      if (action?.ascii) characters.add(action.ascii);
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

test('language and punctuation switches are independent and English Space never selects paused Chinese',() => {
  const state = {raw_input:'ni',candidates:[{id:'first'}]};
  assert.deepEqual(protocolAction({type:'toggle-language'},state,{input:'chinese',punctuation:'english'}),{type:'setModes',inputMode:'english'});
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

test('queued language toggles read authoritative prior response and retain independent punctuation mode',async () => {
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

function response(value) { return {ok:true,status:200,json:async () => value}; }
