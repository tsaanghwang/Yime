// Planning model only: no CSS-pixel-to-millimetre or measured error claims.
export function geometry(diagonal, gap = 2) {
  if (!Number.isFinite(diagonal) || diagonal < 5 || diagonal > 20 || !Number.isFinite(gap) || gap < 0 || gap > 4) throw new RangeError('invalid screen assumptions');
  const width = diagonal * 25.4 * 16 / Math.hypot(16, 10);
  const height = diagonal * 25.4 * 10 / Math.hypot(16, 10);
  return { width, height, keyWidth: (width * .9 - gap * 9) / 10, keyHeight: (height * .65 - gap * 5) / 6, gap };
}

// Abramowitz-Stegun approximation; independent centred Gaussian x/y errors.
function erf(x) {
  const t = 1 / (1 + .3275911 * Math.abs(x));
  return Math.sign(x) * (1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - .284496736) * t + .254829592) * t * Math.exp(-x * x));
}
export function missProbability(width, height, sigma) {
  if (![width, height, sigma].every(x => Number.isFinite(x) && x > 0)) throw new RangeError('positive dimensions required');
  return 1 - erf(width / (2 * Math.SQRT2 * sigma)) * erf(height / (2 * Math.SQRT2 * sigma));
}
export function percentile(values, p) {
  if (!values.length) return null;
  return [...values].sort((a, b) => a - b)[Math.max(0, Math.ceil(values.length * p) - 1)];
}
