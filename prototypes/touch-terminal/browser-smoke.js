// Run with playwright-cli run-code --filename=prototypes/touch-terminal/browser-smoke.js
// The current page must use the isolated Go keyboard-lab loopback service.
async (page) => {
  const base = new URL(page.url()).origin;
  if (!/^http:\/\/127\.0\.0\.1:\d+$/.test(base)) throw new Error('Use the isolated loopback Go service');
  const checks = [], errors = [], external = [];
  const assert = (condition,message) => { if (!condition) throw new Error(message); };
  page.on('pageerror',error => errors.push(String(error)));
  page.on('request',request => { if (!request.url().startsWith(base+'/')) external.push(request.url()); });
  await page.setViewportSize({width:1550,height:1180});
  await page.goto(base);
  await page.locator('#connection.connected').waitFor();
  await page.evaluate(() => document.fonts.ready);
  assert(await page.evaluate(() => Array.from(document.fonts).some(font => font.family === 'YinYuan' && font.status === 'loaded')),'packaged YinYuan font loaded without system installation');
  const layout = await page.evaluate(async () => (await fetch('./data/physical-layout.json')).json());
  assert(await page.locator('.physical-key').count() === 129,'all 129 physical keys rendered');
  assert(await page.locator('#load-error').isHidden(),'live initialization succeeds');
  assert(layout.touchTemplateId,'geometry identity recorded');
  const codingKeys = layout.keys.filter(key => key.yinyuanIds.some(id => !key.disabledYinyuanIds.includes(id)));
  assert(codingKeys.length === 57,'57 currently active ASCII coding keys');
  assert(await page.locator('.physical-key .disabled-yinyuan').count() === 3,'three reserved shared legends shown disabled');
  const candidateKeys = layout.keys.filter(key => key.action.type === 'select');
  assert(candidateKeys.length === 9,'nine fixed candidate positions');
  for (const key of candidateKeys) {
    const button = page.locator(`[data-id="${key.id}"]`);
    assert((await button.innerText()).trim() === String(key.action.ordinal),'concept candidate key shows only its plain ordinal');
    assert(!(await button.getAttribute('aria-label')).includes('⇧'),'concept candidate accessible label does not imply a Shift chord');
  }
  const board = await page.locator('#keyboard').boundingBox();
  for (const key of layout.keys) {
    const box = await page.locator(`[data-id="${key.id}"]`).boundingBox();
    assert(Math.abs(box.x-(board.x+key.x/layout.bounds.width*board.width+2)) < 1.1,`${key.id} KLE x`);
    assert(Math.abs(box.y-(board.y+key.y/layout.bounds.height*board.height+2)) < 1.1,`${key.id} KLE y`);
  }
  checks.push('129-key source geometry, 57 active ASCII keys, 3 disabled shared labels, 9 fixed candidate keys');
  const waitCode = async code => page.waitForFunction(value => document.querySelector('#code').textContent === (value || '—'),code);
  const waitCommit = async value => page.waitForFunction(expected => document.querySelector('#committed').value === expected,value);
  const clear = async () => {
    await page.locator('#keyboard').focus();
    await page.keyboard.press('Escape');
    await waitCode('');
  };
  for (const key of codingKeys) {
    await page.locator(`[data-id="${key.id}"]`).click();
    await waitCode(key.action.ascii);
    await clear();
  }
  checks.push('each active physical key appends exactly its ASCII once, including uppercase and shared keys');
  const samples = {variable:'ni',full:'niii',shorthand:'ni'};
  const pointerSamples = {variable:'hau',full:'haau',shorthand:'hau'};
  for (const [mode,code] of Object.entries(samples)) {
    await page.locator('#code-mode').selectOption(mode);
    await page.waitForFunction(() => !document.querySelector('#code-mode').disabled);
    await page.locator('#keyboard').focus();
    await page.keyboard.type(code);
    await waitCode(code);
    const ordinals = await page.locator('.candidate .ordinal').allTextContents();
    assert(ordinals.length > 0 && ordinals.every((label,index) => label === String(index+1)),'candidate strip uses matching plain ordinals');
    await page.locator('.candidate').getByText('你',{exact:true}).click();
    await waitCode('');
    assert((await page.locator('#committed').inputValue()).endsWith('你'),`${mode} real engine Chinese commit`);
    const pointerCode = pointerSamples[mode];
    let partial = '';
    for (const ascii of pointerCode) {
      const key = codingKeys.find(item => item.action.ascii === ascii);
      await page.locator(`[data-id="${key.id}"]`).click();
      partial += ascii;
      await waitCode(partial);
    }
    const visible = await page.locator('.candidate span:last-child').allTextContents();
    const ordinal = visible.indexOf('好')+1;
    assert(ordinal > 0,`${mode} virtual sequence offers 好`);
    const physicalCandidate = candidateKeys.find(item => item.action.ordinal === ordinal);
    await page.locator(`[data-id="${physicalCandidate.id}"]`).click();
    await waitCode('');
    assert((await page.locator('#committed').inputValue()).endsWith('好'),`${mode} physical candidate position commits 好`);
    for (let ordinal = 1; ordinal <= 9; ordinal++) {
      await page.locator('#keyboard').focus();
      await page.keyboard.type('n');
      await waitCode('n');
      const expected = await page.locator('.candidate span:last-child').nth(ordinal-1).innerText();
      const before = await page.locator('#committed').inputValue();
      await page.keyboard.press(`Digit${ordinal}`);
      await waitCode('');
      assert(await page.locator('#committed').inputValue() === before+expected,`${mode} bare Digit${ordinal} commits exactly its visible candidate`);
    }
  }
  checks.push('ANSI typing commits 你 and virtual sequence + fixed candidate key commits 好 through all three real indexes');
  await page.locator('#code-mode').selectOption('variable');
  await page.waitForFunction(() => !document.querySelector('#code-mode').disabled);
  await page.locator('#keyboard').focus();
  await page.keyboard.type('ni');
  await waitCode('ni');
  const beforeShift = await page.locator('#committed').inputValue();
  const firstBeforeShift = await page.locator('.candidate span:last-child').first().innerText();
  await page.keyboard.press('Shift+Digit1');
  await waitCommit(beforeShift+firstBeforeShift+'!');
  await waitCode('');
  for (let ordinal = 1; ordinal <= 9; ordinal++) {
    const before = await page.locator('#committed').inputValue();
    const expected = before+'!@#$%^&*('[ordinal-1];
    await page.keyboard.press(`Shift+Digit${ordinal}`);
    await waitCommit(expected);
    assert(await page.locator('#code').innerText() === '—','Shift punctuation writes text, not composition');
  }
  const committedBeforeEmpty = await page.locator('#committed').inputValue();
  await page.keyboard.press('Digit1');
  await waitCommit(committedBeforeEmpty+'1');
  assert(await page.locator('#code').innerText() === '—','empty candidate digit commits without composition');
  await page.keyboard.press('Digit0');
  await waitCommit(committedBeforeEmpty+'10');
  await page.keyboard.type('zzzzzzzzzzzz');
  await waitCode('zzzzzzzzzzzz');
  assert(await page.locator('.candidate').count() === 0,'explicit unmatched composition fixture');
  await page.keyboard.press('Digit9');
  await waitCommit(committedBeforeEmpty+'109');
  assert(await page.locator('#code').innerText() === 'zzzzzzzzzzzz','literal fallback preserves unmatched composition');
  await page.keyboard.press('Shift+Digit2');
  await waitCommit(committedBeforeEmpty+'109@');
  assert(await page.locator('#code').innerText() === 'zzzzzzzzzzzz','literal symbol preserves unmatched composition');
  await clear();
  await page.locator('#keyboard').focus();
  await page.keyboard.type('n');
  await waitCode('n');
  if (await page.locator('#next').isEnabled()) {
    await page.keyboard.press('PageDown');
    await page.waitForFunction(() => document.querySelector('#page-label').textContent === '第 2 页');
    await page.keyboard.press('PageUp');
    await page.waitForFunction(() => document.querySelector('#page-label').textContent === '第 1 页');
  } else throw new Error('Expected a real multi-page n prefix');
  await clear();
  for (const key of ['-','=','_', '+','`','~',';',':',',','<','.', '>','"','{','}','|','?']) {
    const before = await page.locator('#committed').inputValue();
    await page.keyboard.type(key);
    await waitCommit(before+key);
    assert(await page.locator('#code').innerText() === '—',`noncoding punctuation ${key} directly commits`);
  }
  checks.push('all bare 1–9 ordinals in three modes, empty-candidate literal digits, 0 and punctuation commit, unmatched raw preserved, PageUp/PageDown paging');
  for (const ascii of "'[]\\/") {
    await page.keyboard.type(ascii);
    await waitCode(ascii);
    const candidates = await page.locator('.candidate span:last-child').allTextContents();
    assert(candidates.at(-1) === ascii,`coding symbol ${ascii} is the last first-page candidate`);
    assert(candidates.length <= 9,'literal candidate remains within the nine available positions');
    const before = await page.locator('#committed').inputValue();
    const key = candidateKeys.find(item => item.action.ordinal === candidates.length);
    await page.locator(`[data-id="${key.id}"]`).click();
    await waitCode('');
    await waitCommit(before+ascii);
  }
  checks.push('all five exact-single coding symbols can be committed through the last candidate of page one');
  const shiftKey = layout.keys.find(key => key.action.type === 'shift');
  const shiftButton = page.locator(`[data-id="${shiftKey.id}"]`);
  for (const key of layout.keys.filter(key => key.shiftAction)) {
    const before = await page.locator('#committed').inputValue();
    await shiftButton.click();
    assert(await shiftButton.getAttribute('aria-pressed') === 'true','virtual Shift visibly armed');
    const button = page.locator(`[data-id="${key.id}"]`);
    assert((await button.innerText()).trim() === key.shiftAction.ascii,'shifted key shows actual symbol');
    await button.click();
    await waitCommit(before+key.shiftAction.ascii);
    assert(await shiftButton.getAttribute('aria-pressed') === 'false','one printable key consumes Shift');
  }
  for (const ascii of ['n','N']) {
    await shiftButton.click();
    const key = codingKeys.find(item => item.action.ascii === ascii);
    await page.locator(`[data-id="${key.id}"]`).click();
    await waitCode(ascii);
    assert(await shiftButton.getAttribute('aria-pressed') === 'false','fixed letter input consumes symbol latch');
    await clear();
  }
  await shiftButton.click();
  await shiftButton.click();
  assert(await shiftButton.getAttribute('aria-pressed') === 'false','second Shift toggles off');
  await shiftButton.click();
  await clear();
  assert(await shiftButton.getAttribute('aria-pressed') === 'false','Escape resets Shift');
  await shiftButton.click();
  await page.locator('#code-mode').selectOption('full');
  await page.waitForFunction(() => !document.querySelector('#code-mode').disabled);
  assert(await shiftButton.getAttribute('aria-pressed') === 'false','mode change resets Shift');
  await page.locator('#code-mode').selectOption('variable');
  await page.waitForFunction(() => !document.querySelector('#code-mode').disabled);
  checks.push('virtual one-shot symbol Shift covers every existing shifted cap while fixed letter cases remain unchanged');
  for (const ascii of ['n','N','[',']',"'"]) {
    await page.locator('#keyboard').focus();
    await page.keyboard.type(ascii);
    await waitCode(ascii);
    await clear();
  }
  const nKey = codingKeys.find(key => key.action.ascii === 'n');
  const button = page.locator(`[data-id="${nKey.id}"]`);
  const rect = await button.boundingBox();
  await page.mouse.move(rect.x+rect.width/2,rect.y+rect.height/2);
  await page.mouse.down();
  await page.mouse.move(rect.x+rect.width+8,rect.y+rect.height/2);
  await page.mouse.move(rect.x+rect.width/2,rect.y+rect.height/2);
  await page.mouse.up();
  assert(await page.locator('#code').innerText() === '—','drag out then back cancels');
  await button.focus();
  await page.keyboard.press('Space');
  await waitCode('n');
  const textBeforeBlur = await page.locator('#committed').inputValue();
  await shiftButton.click();
  await page.evaluate(() => window.dispatchEvent(new Event('blur')));
  await waitCode('');
  assert(await shiftButton.getAttribute('aria-pressed') === 'false','blur resets Shift');
  assert(await page.locator('#committed').inputValue() === textBeforeBlur,'blur preserves confirmed text');
  checks.push('case-sensitive ANSI, drag cancellation, single keyboard activation and blur cancellation');
  await shiftButton.click();
  await page.locator('#drill').click();
  for (const key of layout.keys) await page.locator(`[data-id="${key.id}"]`).click();
  assert((await page.locator('#drill-status').innerText()).includes('已覆盖 129/129，总点按 129，重复 0'),'all physical key coverage');
  assert(await shiftButton.getAttribute('aria-pressed') === 'true','coverage records never consume or toggle Shift');
  await page.locator('#target-drill').click();
  const target = await page.locator('.physical-key.target').getAttribute('data-id');
  await page.locator(`[data-id="${layout.keys.find(key => key.id !== target).id}"]`).click();
  assert(await page.locator('.physical-key.target').getAttribute('data-id') === target,'wrong target never advances');
  await page.locator('#stop-drill').click();
  await shiftButton.click();
  const downloadEvent = page.waitForEvent('download');
  await page.locator('#export').click();
  const download = await downloadEvent;
  let reportText = '';
  for await (const chunk of await download.createReadStream()) reportText += chunk;
  const report = JSON.parse(reportText);
  assert(report.formatVersion === 4 && report.touchTemplateId === layout.touchTemplateId,'full keyboard report identity');
  assert(report.inputPolicy === 'candidate-or-literal-v1','session report identifies the active digit/punctuation policy');
  assert(report.drills[0].seen.length === 129 && report.drills[1].wrong === 1,'separate drill records');
  assert(report.touches.some(touch => Number.isFinite(touch.pointer?.up?.keyLocal?.x)),'pointer coordinates recorded');
  checks.push('129-key coverage, retry target semantics and geometry-aware report export');
  await page.screenshot({path:'output/playwright/ascii-keyboard-desktop.png',fullPage:true});
  const context = await page.context().browser().newContext({viewport:{width:390,height:844},hasTouch:true,isMobile:true,deviceScaleFactor:1});
  try {
    const touchPage = await context.newPage();
    touchPage.on('pageerror',error => errors.push(String(error)));
    await touchPage.goto(base);
    await touchPage.locator('#connection.connected').waitFor();
    const touchKey = touchPage.locator(`[data-id="${codingKeys[0].id}"]`);
    await touchKey.scrollIntoViewIfNeeded();
    await touchKey.tap();
    await touchPage.waitForFunction(value => document.querySelector('#code').textContent === value,codingKeys[0].action.ascii);
    await touchPage.locator('#clear').tap();
    await touchPage.waitForFunction(() => document.querySelector('#code').textContent === '—');
    await touchKey.scrollIntoViewIfNeeded();
    const touchRect = await touchKey.boundingBox();
    const cdp = await context.newCDPSession(touchPage);
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:touchRect.x+12,y:touchRect.y+12}]});
    await cdp.send('Input.dispatchTouchEvent',{type:'touchCancel',touchPoints:[]});
    assert(await touchPage.locator('#code').innerText() === '—','touchCancel does not input');
    assert(await touchPage.evaluate(() => document.documentElement.scrollWidth <= innerWidth),'narrow layout has no document overflow');
    await touchPage.screenshot({path:'output/playwright/ascii-keyboard-narrow.png',fullPage:true});
    checks.push('390px emulated touch single dispatch, touchCancel and no page-wide overflow');
  } finally { await context.close(); }
  assert(errors.length === 0,`browser errors: ${errors.join('; ')}`);
  assert(external.length === 0,`external requests: ${external.join('; ')}`);
  return {ok:true,checks,errors,external,hardwareAcceptance:false};
}
