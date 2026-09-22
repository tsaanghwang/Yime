import test from 'node:test';
import assert from 'node:assert/strict';
import {geometry, missProbability, percentile} from './geometry.mjs';
test('60-key 10x6 geometry accounts for all gaps and reserved screen area', () => {
  for (const inches of [7, 8, 10.1]) {
    const g = geometry(inches);
    assert.ok(Math.abs(10 * g.keyWidth + 9 * g.gap - .9 * g.width) < 1e-9);
    assert.ok(Math.abs(6 * g.keyHeight + 5 * g.gap - .65 * g.height) < 1e-9);
  }
  assert.ok(geometry(7).keyHeight > 8 && geometry(7).keyHeight < 9);
  assert.ok(geometry(10.1).keyHeight > 13);
  assert.throws(() => geometry(NaN));
});
test('Gaussian sensitivity is not an observed wrong-key rate', () => {
  assert.ok(Math.abs(missProbability(8, 8, 2) - .08893) < .0001);
  assert.ok(missProbability(12, 12, 2) < missProbability(9, 9, 2));
  assert.ok(missProbability(9, 9, 3) > missProbability(9, 9, 2));
  assert.throws(() => missProbability(9, 9, 0));
  assert.equal(percentile([], .95), null);
  assert.equal(percentile([4, 1, 3, 2], .95), 4);
});
