// playwright-cli run-code --filename=prototypes/touch-terminal/browser-smoke.js
// Run only against the isolated loopback experiment, never an installed IME.
async (page) => {
  const base = new URL(page.url()).origin;
  if (!/^http:\/\/127\.0\.0\.1:\d+$/.test(base)) throw new Error('Use the isolated loopback Go service');
  const checks=[],errors=[],external=[];
  const assert=(condition,message) => { if (!condition) throw new Error(message); };
  page.on('pageerror',error => errors.push(String(error)));
  page.on('request',request => { if (!request.url().startsWith(base+'/')) external.push(request.url()); });
  await page.setViewportSize({width:1800,height:1180});
  await page.goto(base);
  await page.locator('#connection.connected').waitFor();
  const layout=await page.evaluate(async () => (await fetch('./data/physical-layout.json')).json());
  assert(layout.formatVersion===3 && layout.keys.length===138,'current 138-key layered layout loaded');
  assert(await page.locator('.physical-key').count()===138,'all physical keys rendered');
  assert((layout.disabledYinyuanIds||[]).length===0,'M25–M27 enabled');
  await page.evaluate(() => document.fonts.ready);
  assert(await page.evaluate(() => Array.from(document.fonts).some(f => f.family==='YinYuan' && f.status==='loaded')),'local YinYuan font loaded');
  const button=key => page.locator(`[data-id="${key.id}"]`);
  const find=(predicate) => { const key=layout.keys.find(predicate);assert(key,'required physical key');return key; };
  const shift=find(k=>k.action.type==='shift');
  const waitCode=code => page.waitForFunction(v=>document.querySelector('#code').textContent===(v||'—'),code);
  const waitText=value => page.waitForFunction(v=>document.querySelector('#committed').value===v,value);
  const text=()=>page.locator('#committed').inputValue();
  const clear=async()=>{await page.locator('#keyboard').focus();await page.keyboard.press('Escape');await waitCode('');};
  const pathFor=ascii => {
    if(ascii===' ')return {key:find(k=>k.action.type==='confirm'&&k.action.key==='Space'),shifted:false};
    for(const zone of ['main','left','right'])for(const key of layout.keys.filter(k=>k.zone===zone)) {
      if(key.action.ascii===ascii)return {key,shifted:false};
      if(key.shiftAction?.ascii===ascii)return {key,shifted:true};
    }
    throw new Error(`No virtual path for ASCII ${ascii.charCodeAt(0)}`);
  };
  const tapPath=async path=>{if(path.shifted)await button(shift).click();await button(path.key).click();};
  const setInput=async english=>{
    if((await page.locator('#input-mode').getAttribute('aria-pressed'))!==String(english))await page.locator('#input-mode').click();
    await page.waitForFunction(v=>document.querySelector('#input-mode').getAttribute('aria-pressed')===String(v),english);
  };
  const setPunctuation=async chinese=>{
    if((await page.locator('#punctuation-mode').getAttribute('aria-pressed'))!==String(chinese))await page.locator('#punctuation-mode').click();
    await page.waitForFunction(v=>document.querySelector('#punctuation-mode').getAttribute('aria-pressed')===String(v),chinese);
  };
  const ascii95=Array.from({length:95},(_,i)=>String.fromCharCode(32+i)).join('');
  await setInput(true);
  let expected=await text();
  for(const ascii of ascii95){await tapPath(pathFor(ascii));expected+=ascii;await waitText(expected);}
  await page.locator('#keyboard').focus();
  await page.keyboard.type(ascii95);
  expected+=ascii95;await waitText(expected);await waitCode('');
  checks.push('all 95 printable ASCII round-trip through virtual keys and ANSI in English input/English punctuation');
  await setInput(false);
  const semanticPaths=[];
  for(const key of layout.keys){
    for(const id of key.baseYinyuanIds||[])semanticPaths.push({id,key,shifted:false,action:key.action});
    for(const id of key.shiftYinyuanIds||[])semanticPaths.push({id,key,shifted:true,action:key.shiftAction});
  }
  assert(semanticPaths.length===75 && new Set(semanticPaths.map(p=>p.id)).size===75,'NM60 plus R04–R18 each have one explicit layer path');
  for(const path of semanticPaths){await tapPath(path);await waitCode(path.action.ascii);await clear();}
  checks.push('all 75 semantic ID layer paths append their canonical ASCII, including M25–M27 and all 15 R carriers');
  const samples={variable:'ni',full:'niii',shorthand:'ni'};
  for(const [mode,code]of Object.entries(samples)){
    await page.locator('#code-mode').selectOption(mode);await page.waitForFunction(()=>!document.querySelector('#code-mode').disabled);
    await page.locator('#keyboard').focus();await page.keyboard.type(code);await waitCode(code);
    await page.locator('.candidate').getByText('你',{exact:true}).click();await waitCode('');
    assert((await text()).endsWith('你'),`${mode} actual engine commits 你`);
    await page.keyboard.type('n');await waitCode('n');
    const first=await page.locator('.candidate span:last-child').first().innerText(),before=await text();
    await tapPath(pathFor('1'));await waitCode('');await waitText(before+first);
  }
  await page.locator('#code-mode').selectOption('variable');await page.waitForFunction(()=>!document.querySelector('#code-mode').disabled);
  await page.locator('#keyboard').focus();await page.keyboard.type('ni');await waitCode('ni');
  const sideSlash=find(k=>k.zone==='left'&&k.action.type==='literal'&&k.action.ascii==='/');
  let before=await text();await setPunctuation(true);await button(sideSlash).click();await waitText(before+'/');await waitCode('ni');
  before=await text();await page.locator('#keyboard').dispatchEvent('keydown',{key:'1',code:'Numpad1'});await waitText(before+'1');await waitCode('ni');
  await setInput(true);assert((await page.locator('#composition').innerText()).includes('暂停'),'English visibly pauses pending Chinese');
  before=await text();await page.keyboard.type('Ab1.');await waitText(before+'Ab1。');await waitCode('ni');
  before=await text();await page.keyboard.press('Space');await page.keyboard.press('Enter');await waitText(before+' \n');await waitCode('ni');
  await setPunctuation(false);before=await text();await page.keyboard.type('.');await waitText(before+'.');await waitCode('ni');
  await setInput(false);const resumed=await page.locator('.candidate span:last-child').first().innerText();
  before=await text();await page.keyboard.press('Digit1');await waitText(before+resumed);await waitCode('');
  checks.push('three engine modes, main digit selection, side/ANSI-numpad literal bypass, independent punctuation and paused composition round-trip');
  const leftLock=find(k=>k.zone==='left'&&k.action.type==='toggle-number'),rightLock=find(k=>k.zone==='right'&&k.action.type==='toggle-number');
  await button(leftLock).click();
  assert(await button(leftLock).getAttribute('aria-pressed')==='false','left switched to edit');
  assert(await button(rightLock).getAttribute('aria-pressed')==='true','right remains numeric');
  const leftFive=find(k=>k.zone==='left'&&k.action.ascii==='5'),rightFive=find(k=>k.zone==='right'&&k.action.ascii==='5');
  before=await text();await button(leftFive).click();assert(await text()===before,'edit 5 is a no-op');
  await button(rightFive).click();await waitText(before+'5');
  const leftHome=find(k=>k.zone==='left'&&k.editAction?.key==='Home');await button(leftHome).click();
  assert(await page.locator('#committed').evaluate(e=>e.selectionStart===e.value.slice(0,e.selectionStart).lastIndexOf('\n')+1),'side Home edits page cursor');
  await button(leftLock).click();
  checks.push('independent left/right Num Lock, editing 5 no-op and local Home navigation');
  const iso=layout.keys.filter(k=>k.rectangles.length>1);
  assert(iso.length===2,'two mirrored ISO keys');
  for(const key of iso){
    await button(key).scrollIntoViewIfNeeded();
    const box=await button(key).boundingBox();
    const metrics=await page.evaluate(async k=>{const {keyShape}=await import('./geometry.mjs');return keyShape(k);},key);
    assert(metrics.width===2 && metrics.height===2,'ISO union remains 2 by 2 bounds');
    const mirrored=metrics.left<0;
    const hole={x:box.x+box.width*(mirrored?.03:.97),y:box.y+box.height*.8};
    assert(await page.evaluate(({x,y,id})=>document.elementFromPoint(x,y)?.closest('[data-id]')?.dataset.id!==id,{...hole,id:key.id}),'missing corner is not painted/hit as ISO key');
    before=await text();
    await page.mouse.move(box.x+box.width*.5,box.y+box.height*.25);await page.mouse.down();
    await page.mouse.move(hole.x,hole.y);await page.mouse.up();
    assert(await text()===before,'dragging into ISO missing corner cancels');
    await waitCode('');
  }
  checks.push('ISO Tab/Backspace clipped union, mirrored missing-corner hit rejection and drag cancellation');
  const shiftedLetter=semanticPaths.find(p=>p.shifted&&p.action.ascii==='Q');
  assert(shiftedLetter,'explicit A→Q layer exists');
  await page.locator('#keyboard').focus();await page.keyboard.down('Shift');
  assert(await button(shift).getAttribute('aria-pressed')==='true','physical held Shift lights virtual upper layer');
  await page.keyboard.press('KeyA');await page.keyboard.up('Shift');await waitCode('A');await clear();
  await button(shift).click();await button(shiftedLetter.key).click();await waitCode('Q');await clear();
  const caps=find(k=>k.action.type==='unsupported'&&(k.action.label||'').includes('Caps'));
  before=await text();await button(caps).click();assert(await text()===before,'concept Caps has no side effects');
  await button(shift).click();await page.evaluate(()=>window.dispatchEvent(new Event('blur')));await waitCode('');
  assert(await button(shift).getAttribute('aria-pressed')==='false','blur clears all Shift state');
  checks.push('explicit virtual A→Q shift versus unmodified ANSI event.key, Caps schematic and blur safety');
  await page.locator('#drill').click();
  for(const key of layout.keys)await button(key).click();
  assert((await page.locator('#drill-status').innerText()).includes('已覆盖 138/138，总点按 138，重复 0'),'138-key coverage');
  assert(await button(leftLock).getAttribute('aria-pressed')==='true'&&await button(rightLock).getAttribute('aria-pressed')==='true','drill never toggles number modes');
  const downloading=page.waitForEvent('download');await page.locator('#export').click();const download=await downloading;
  let reportText='';for await(const chunk of await download.createReadStream())reportText+=chunk;
  const report=JSON.parse(reportText);
  assert(report.formatVersion===5&&report.inputPolicy==='concept-keyboard-modes-v2','new session report policy/version');
  assert(report.touchTemplateId===layout.touchTemplateId&&report.drills[0].seen.length===138,'report identifies exact board and coverage');
  await page.screenshot({path:'output/playwright/concept-138-desktop.png',fullPage:true});
  const context=await page.context().browser().newContext({viewport:{width:1800,height:1000},hasTouch:true,isMobile:true,deviceScaleFactor:1});
  try{
    const touch=await context.newPage();touch.on('pageerror',e=>errors.push(String(e)));await touch.goto(base);await touch.locator('#connection.connected').waitFor();
    await touch.locator(`[data-id="${shift.id}"]`).scrollIntoViewIfNeeded();
    const shiftBox=await touch.locator(`[data-id="${shift.id}"]`).boundingBox(),keyBox=await touch.locator(`[data-id="${shiftedLetter.key.id}"]`).boundingBox();
    const p1={id:1,x:shiftBox.x+shiftBox.width/2,y:shiftBox.y+shiftBox.height/2},p2={id:2,x:keyBox.x+keyBox.width/2,y:keyBox.y+keyBox.height/2};
    const cdp=await context.newCDPSession(touch);
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[p1]});
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[p1,p2]});
    // CDP lists the released touch here; release Shift before the character.
    await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[p1]});
    await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
    await touch.waitForFunction(()=>document.querySelector('#code').textContent==='Q');
    assert(await touch.locator(`[data-id="${shift.id}"]`).getAttribute('aria-pressed')==='false','held Shift consumed without leaving a latch');
    await touch.locator('#clear').tap();await touch.waitForFunction(()=>document.querySelector('#code').textContent==='—');
    await touch.setViewportSize({width:390,height:844});
    const key=touch.locator(`[data-id="${shiftedLetter.key.id}"]`);await key.scrollIntoViewIfNeeded();await key.tap();
    await touch.waitForFunction(()=>document.querySelector('#code').textContent==='A');
    assert(await touch.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'390px view has no page-wide overflow');
    await touch.screenshot({path:'output/playwright/concept-138-narrow.png',fullPage:true});
    checks.push('emulated two-finger held Shift with early Shift release, narrow touch and no page-wide overflow');
  }finally{await context.close();}
  assert(errors.length===0,`browser errors: ${errors.join('; ')}`);assert(external.length===0,`external requests: ${external.join('; ')}`);
  return {ok:true,checks,errors,external,hardwareAcceptance:false};
}
