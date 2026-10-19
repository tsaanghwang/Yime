// playwright-cli run-code --filename=prototypes/touch-terminal/browser-smoke.js
// Real local Go engine; all browser/touch automation remains hardwareAcceptance=false.
async (page) => {
  const base=new URL(page.url()).origin;
  if(!/^http:\/\/127\.0\.0\.1:\d+$/.test(base))throw new Error('Use the isolated loopback Go service');
  const checks=[],errors=[],external=[],requests=[];
  const assert=(condition,message)=>{if(!condition)throw new Error(message);};
  page.on('pageerror',error=>errors.push(String(error)));
  page.on('request',request=>{requests.push(request.url());if(!request.url().startsWith(base+'/'))external.push(request.url());});
  await page.setViewportSize({width:1800,height:1180});await page.goto(base);
  await page.locator('#connection.connected').waitFor();
  await page.waitForFunction(()=>document.querySelector('#punctuation-mode').textContent==='标点：中文');
  const layout=await page.evaluate(async()=>(await fetch('./data/physical-layout.json')).json());
  assert(layout.formatVersion===4&&layout.keys.length===134,'CN/EN134 generated layout');
  assert(await page.locator('.physical-key').count()===134,'134 rendered physical nodes');
  const button=key=>page.locator(`[data-id="${key.id}"]`);
  const find=predicate=>{const key=layout.keys.find(predicate);assert(key,'required key');return key;};
  const shift=find(k=>k.action.type==='shift'),toggle=find(k=>k.action.type==='toggle-layout');
  const waitCode=code=>page.waitForFunction(v=>document.querySelector('#code').textContent===(v||'—'),code);
  const text=()=>page.locator('#committed').inputValue();
  const waitText=value=>page.waitForFunction(v=>document.querySelector('#committed').value===v,value);
  const clear=async()=>{await page.locator('#keyboard').focus();await page.keyboard.press('Escape');await waitCode('');};
  const setInput=async english=>{
    if(await page.locator('#input-mode').getAttribute('aria-pressed')!==String(english))await page.locator('#input-mode').click();
    await page.waitForFunction(v=>document.querySelector('#input-mode').getAttribute('aria-pressed')===String(v),english);
  };
  const setLayout=async english=>{
    if(await button(toggle).getAttribute('aria-pressed')!==String(english))await button(toggle).click();
    await page.waitForFunction(({id,v})=>document.querySelector(`[data-id="${id}"]`).getAttribute('aria-pressed')===String(v),{id:toggle.id,v:english});
  };
  const pathFor=(ascii,english=false)=>{
    if(ascii===' ')return{key:find(k=>k.action.type==='confirm'&&k.action.key==='Space'),shifted:false};
    for(const zone of ['main','left','right'])for(const baseKey of layout.keys.filter(k=>k.zone===zone)){
      const key=english?baseKey.english:baseKey;
      if(key.action.ascii===ascii)return{key:baseKey,shifted:false};
      if(key.shiftAction?.ascii===ascii)return{key:baseKey,shifted:true};
    }
    throw new Error('No virtual path '+JSON.stringify(ascii));
  };
  const tap=async path=>{if(path.shifted)await button(shift).click();await button(path.key).click();};
  const snapshot=()=>page.evaluate(()=>{
    window.__keyNodes??=Array.from(document.querySelectorAll('.physical-key'));
    window.__legendNodes??=window.__keyNodes.map(k=>Array.from(k.querySelectorAll('.key-legend')));
    window.__keyColors??=window.__keyNodes.map(k=>getComputedStyle(k).backgroundColor);
    return window.__keyNodes.length;
  });
  await snapshot();await page.screenshot({path:'output/playwright/concept-134-cn.png',fullPage:true});
  await setInput(true);await setLayout(true);
  assert(await page.locator('.physical-key:disabled').count()===23,'23 EN keys disabled');
  assert(await page.evaluate(()=>window.__keyNodes.every((node,i)=>node===document.querySelectorAll('.physical-key')[i]&&window.__legendNodes[i].every((span,j)=>span===node.querySelectorAll('.key-legend')[j])&&window.__keyColors[i]===getComputedStyle(node).backgroundColor)),'key/legend nodes and colors reused');
  let expected=await text();
  for(const ascii of Array.from({length:95},(_,i)=>String.fromCharCode(32+i))){await tap(pathFor(ascii,true));expected+=ascii;await waitText(expected);}
  await page.locator('#keyboard').focus();await page.keyboard.type(' aAzZ0123!?');expected+=' aAzZ0123!?';await waitText(expected);
  checks.push('all95 printable ASCII through EN virtual layers; ANSI event.key unchanged;23 disabled keys;node/color reuse');
  await page.screenshot({path:'output/playwright/concept-134-en.png',fullPage:true});
  await setLayout(false);
  const beforeRequests=requests.length;
  for(let i=0;i<200;i++)await button(toggle).click();
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  assert(requests.length===beforeRequests,'layout switching performs no HTTP requests');
  assert(await button(toggle).getAttribute('aria-pressed')==='false','200 toggles return original');
  await setLayout(true);
  const first=pathFor('q',true);await tap(first);expected+='q';await waitText(expected);
  await setInput(false);assert(await button(toggle).getAttribute('aria-pressed')==='false','Chinese always uses CN');
  await setInput(true);assert(await button(toggle).getAttribute('aria-pressed')==='true','English preference restored');
  checks.push('200 repeated local layout switches without requests;first-key mapping;English preference restored across language changes');
  await setInput(false);
  const semantic=[];
  for(const key of layout.keys)for(const [field,shifted,name]of [['baseYinyuanIds',false,'action'],['shiftYinyuanIds',true,'shiftAction']])for(const id of key[field]||[])semantic.push({id,key,shifted,ascii:key[name].ascii});
  assert(semantic.length===75,'75 independent semantic entrances');
  for(const path of semantic){await tap(path);await waitCode(path.ascii);await clear();}
  for(const [mode,code]of Object.entries({variable:'ni',full:'niii',shorthand:'ni'})){
    await page.locator('#code-mode').selectOption(mode);await page.waitForFunction(()=>!document.querySelector('#code-mode').disabled);
    await page.locator('#keyboard').focus();await page.keyboard.type(code);await waitCode(code);
    await page.locator('.candidate').getByText('你',{exact:true}).click();await waitCode('');
    assert((await text()).endsWith('你'),mode+' real engine commit');
  }
  await page.locator('#code-mode').selectOption('variable');await page.waitForFunction(()=>!document.querySelector('#code-mode').disabled);
  await page.locator('#keyboard').focus();await page.keyboard.type('ni');await waitCode('ni');
  let before=await text();await setInput(true);await setLayout(true);await tap(pathFor('q',true));await waitText(before+'q');await waitCode('ni');
  await setInput(false);const candidate=await page.locator('.candidate span:last-child').first().innerText();
  before=await text();await tap(pathFor('1'));await waitText(before+candidate);await waitCode('');
  checks.push('75 semantic layer paths;three real engine modes;paused Chinese survives layouts;main digit selects current candidate');
  // Optional entrances cannot alter an ID-bearing key, and preserve pending code.
  const entrance=find(k=>k.shiftAction?.literalEntry&&k.shiftAction.ascii==='!');
  await tap({key:entrance,shifted:true});await waitCode('!');await clear();
  await page.locator('#literal-entries').click();
  await page.locator('#keyboard').focus();await page.keyboard.type('ni');await waitCode('ni');
  before=await text();await tap({key:entrance,shifted:true});await waitText(before+'！');await waitCode('ni');await clear();
  before=await text();
  for(const char of '——······')await tap(pathFor(char));
  await waitText(before+'——……');
  await page.locator('#literal-entries').click();
  checks.push('32 reserved literal entrances toggle;coding layers protected;Chinese punctuation and explicit dash/ellipsis consolidation');
  const left=find(k=>k.zone==='left'&&k.action.type==='toggle-number'),right=find(k=>k.zone==='right'&&k.action.type==='toggle-number');
  await button(left).click();assert(await button(left).getAttribute('aria-pressed')==='false'&&await button(right).getAttribute('aria-pressed')==='true','independent Num Lock');
  before=await text();await button(find(k=>k.zone==='left'&&k.action.ascii==='5')).click();assert(await text()===before,'edit5 noop');await button(left).click();
  // Drag cancellation against actual rendered ISO missing corners.
  for(const key of layout.keys.filter(k=>k.rectangles.length>1)){
    await button(key).scrollIntoViewIfNeeded();const box=await button(key).boundingBox();
    const shape=await page.evaluate(async k=>(await import('./geometry.mjs')).keyShape(k),key);
    const points=[];
    for(const x of [.05,.5,.95])for(const y of [.05,.5,.95]){
      const ux=shape.left+x*shape.width,uy=shape.top+y*shape.height;
      points.push({x,y,inside:shape.rectangles.some(r=>ux>=r.x&&ux<r.x+r.width&&uy>=r.y&&uy<r.y+r.height)});
    }
    const inside=points.find(p=>p.inside),hole=points.find(p=>!p.inside);assert(inside&&hole,'ISO has actual missing corner');
    before=await text();await page.mouse.move(box.x+box.width*inside.x,box.y+box.height*inside.y);await page.mouse.down();
    await page.mouse.move(box.x+box.width*hole.x,box.y+box.height*hole.y);await page.mouse.up();assert(await text()===before,'ISO notch drag cancels');
  }
  await clear();await page.locator('#drill').click();for(const key of layout.keys)await button(key).click();
  assert((await page.locator('#drill-status').innerText()).includes('134/134'),'CN134 coverage');
  await setInput(true);await setLayout(true);await page.locator('#drill').click();for(const key of layout.keys.filter(k=>!k.english.disabled))await button(key).click();
  assert((await page.locator('#drill-status').innerText()).includes('111/111'),'EN111 enabled coverage');
  checks.push('independent Num Lock;edit5;ISO notch cancellation;CN134 and EN111 enabled-key drills');
  // CDP produces browser touch events, not real fingers or hardware acceptance.
  const cdp=await page.context().newCDPSession(page);
  await cdp.send('Emulation.setTouchEmulationEnabled',{enabled:true,maxTouchPoints:10});
  const centre=async key=>{await button(key).scrollIntoViewIfNeeded();const box=await button(key).boundingBox();return{x:box.x+box.width/2,y:box.y+box.height/2};};
  const p1={id:1,...await centre(shift)},p2={id:2,...await centre(first.key)};
  before=await text();
  await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[p1]});
  await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[p1,p2]});
  await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[p2]});
  await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  await waitText(before+'Q');
  assert(await button(shift).getAttribute('aria-pressed')==='false','held Shift consumed without latching');
  await button(shift).click();await setLayout(false);
  assert(await button(shift).getAttribute('aria-pressed')==='false','layout change clears one-shot Shift');
  await setLayout(true);await tap(first);await waitText(before+'Qq');
  await cdp.send('Emulation.setTouchEmulationEnabled',{enabled:false});await cdp.detach();
  checks.push('browser-simulated two-finger Shift release ordering;layout boundary clears Shift');
  const downloading=page.waitForEvent('download');await page.locator('#export').click();const download=await downloading;
  let reportText='';for await(const chunk of await download.createReadStream())reportText+=chunk;
  const report=JSON.parse(reportText);assert(report.formatVersion===7&&report.touchTemplateId===layout.touchTemplateId,'report layout provenance');
  assert(report.layoutSwitchHandlerToFrameMs.length>=200,'layout timing samples');
  assert(report.hardwareAcceptance===false,'automation is not physical acceptance');
  const samples=report.layoutSwitchHandlerToFrameMs.slice(2,202).sort((a,b)=>a-b),p=q=>samples[Math.ceil(samples.length*q)-1];
  await page.reload();await page.locator('#connection.connected').waitFor();await setInput(true);assert(await button(toggle).getAttribute('aria-pressed')==='true','preference persists on reload');
  await page.setViewportSize({width:390,height:900});await page.screenshot({path:'output/playwright/concept-134-narrow.png',fullPage:true});
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'narrow page does not overflow horizontally');
  assert(errors.length===0&&external.length===0,'no page errors or external requests');
  return {passed:true,checks,errors,external,layoutId:layout.layoutId,touchTemplateId:layout.touchTemplateId,
    layoutSwitch:{samples:samples.length,p50:p(.5),p95:p(.95),max:samples.at(-1),metric:'handler-to-requestAnimationFrame;not end-to-end touch'},
    hardwareAcceptance:false};
}
