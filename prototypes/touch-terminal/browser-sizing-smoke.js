async (page)=>{
  const base=new URL(page.url()).origin;
  await page.setViewportSize({width:2560,height:1440});await page.goto(base);await page.locator('#connection.connected').waitFor();
  await page.locator('.sizing-controls summary').click();
  await page.locator('#screen-width-mm').fill('597.73');await page.locator('#apply-screen-size').click();
  const width=()=>page.locator('#keyboard').evaluate(el=>el.getBoundingClientRect().width);
  const before=await width(),screenWidth=await page.evaluate(()=>screen.width);
  if(Math.abs(before-471.4875*screenWidth/597.73)>.1)throw new Error('physical pitch differs from calibrated screen width');
  await page.evaluate(()=>window.__sizingNodes=Array.from(document.querySelectorAll('.physical-key')));
  await page.locator('#ruler-observed-mm').fill('80');await page.locator('#calibrate-ruler').click();
  const after=await width();if(Math.abs(after/before-1.25)>.001)throw new Error('ruler correction did not apply');
  if(!await page.evaluate(()=>window.__sizingNodes.every((n,i)=>n===document.querySelectorAll('.physical-key')[i])))throw new Error('ruler correction recreated key nodes');
  await page.reload();await page.locator('#connection.connected').waitFor();if(Math.abs(await width()-after)>.1)throw new Error('calibration did not persist');
  await page.locator('.sizing-controls summary').click();await page.locator('#apply-screen-size').click();
  await page.screenshot({path:'output/playwright/desktop-stage-physical-size.png',fullPage:true});
  await page.setViewportSize({width:390,height:900});
  if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth))throw new Error('physical keyboard escaped local scroller');
  if(Math.abs(await width()-before)>.1)throw new Error('narrow viewport silently shrank physical keys');
  return {passed:true,unitMM:19.05,fullWidthMM:471.4875,estimatedWidthCSS:before,correctedWidthCSS:after,correction:1.25,localScroll:true,hardwareAcceptance:false};
}
