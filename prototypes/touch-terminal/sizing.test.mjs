import test from 'node:test';
import assert from 'node:assert/strict';
import {UNIT_MM,physicalSize,estimatedPixelsPerMM,rulerCorrection,displayFingerprint} from './sizing.mjs';
test('full-size and reserved 17u dimensions retain the same physical pitch',()=>{
  assert.equal(UNIT_MM,19.05);
  assert.equal(physicalSize({width:24.75,height:7.25},4).widthMM,471.4875);
  assert.equal(physicalSize({width:17,height:7.25},4).widthMM,323.85);
});
test('a ruler measurement corrects physical size without using Windows scale or DPR',()=>{
  const initial=estimatedPixelsPerMM(2560,597.73),fixed=rulerCorrection(initial,80);
  assert.equal(fixed/initial,1.25);
  assert.notEqual(displayFingerprint(2560,1440,1),displayFingerprint(2560,1440,2));
  for(const bad of [0,-1,NaN,Infinity]) assert.throws(()=>rulerCorrection(initial,bad));
});
