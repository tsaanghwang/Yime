import test from 'node:test';
import assert from 'node:assert/strict';
import {geometry, missProbability, percentile,keyShape,keyContainsPoint} from './geometry.mjs';
test('60-key 10x6 geometry accounts for all gaps and reserved screen area', () => {
  for (const inches of [7, 8, 10.1]) {
    const g = geometry(inches);
    assert.ok(Math.abs(10 * g.keyWidth + 9 * g.gap - .9 * g.width) < 1e-9);
    assert.ok(Math.abs(6 * g.keyHeight + 5 * g.gap - .65 * g.height) < 1e-9);
  }
  assert.ok(geometry(7).keyHeight > 8 && geometry(7).keyHeight < 9);
  assert.ok(geometry(10.1).keyHeight > 13);
  const wide = geometry(15.6, 2, 16, 9, 10, 6);
  assert.ok(Math.abs(10 * wide.keyWidth + 9 * wide.gap - .9 * wide.width) < 1e-9);
  assert.equal(wide.aspectHeight, 9);
  assert.throws(() => geometry(NaN));
  assert.throws(() => geometry(10, 2, 0, 9));
});

test('mirrored ISO keys retain their two-rectangle union and reject the empty lower corner',() => {
  const box = {left:100,top:100,width:200,height:200};
  const left = {width:1.75,height:2,rectangles:[{x:0,y:0,width:1.75,height:2},{x:0,y:0,width:2,height:1}]};
  const right = {width:1.75,height:2,rectangles:[{x:0,y:0,width:1.75,height:2},{x:-.25,y:0,width:2,height:1}]};
  for (const key of [left,right]) {
    const shape = keyShape(key);
    assert.equal(shape.width,2);
    assert.equal(shape.height,2);
    assert.ok(shape.polygon.includes('50%'));
    assert.equal(keyContainsPoint(key,{clientX:200,clientY:250},box),true);
    assert.equal(keyContainsPoint(key,{clientX:200,clientY:150},box),true);
    assert.equal(keyContainsPoint(key,{clientX:300,clientY:150},box),false);
  }
  assert.equal(keyShape(right).left,-.25);
  assert.equal(keyContainsPoint(left,{clientX:290,clientY:250},box),false);
  assert.equal(keyContainsPoint(left,{clientX:290,clientY:150},box),true);
  assert.equal(keyContainsPoint(right,{clientX:110,clientY:250},box),false);
  assert.equal(keyContainsPoint(right,{clientX:110,clientY:150},box),true);
  assert.throws(() => keyShape({rectangles:[{x:0,y:0,width:0,height:1}]}));
  assert.throws(() => keyShape({rectangles:[{x:0,y:0,width:1,height:1},{x:2,y:0,width:1,height:1}]}));
});
test('Gaussian sensitivity is not an observed wrong-key rate', () => {
  assert.ok(Math.abs(missProbability(8, 8, 2) - .08893) < .0001);
  assert.ok(missProbability(12, 12, 2) < missProbability(9, 9, 2));
  assert.ok(missProbability(9, 9, 3) > missProbability(9, 9, 2));
  assert.throws(() => missProbability(9, 9, 0));
  assert.equal(percentile([], .95), null);
  assert.equal(percentile([4, 1, 3, 2], .95), 4);
});
