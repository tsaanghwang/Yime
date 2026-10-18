// Planning model only: no CSS-pixel-to-millimetre or measured error claims.
export function geometry(diagonal, gap = 2, aspectWidth = 16, aspectHeight = 10, columns = 10, rows = 6) {
  const positive = [aspectWidth, aspectHeight, columns, rows].every(value => Number.isFinite(value) && value > 0);
  if (!Number.isFinite(diagonal) || diagonal < 5 || diagonal > 80 || !Number.isFinite(gap) || gap < 0 || gap > 4 || !positive) throw new RangeError('invalid screen assumptions');
  const width = diagonal * 25.4 * aspectWidth / Math.hypot(aspectWidth, aspectHeight);
  const height = diagonal * 25.4 * aspectHeight / Math.hypot(aspectWidth, aspectHeight);
  return { width, height, keyWidth: (width * .9 - gap * (columns - 1)) / columns, keyHeight: (height * .65 - gap * (rows - 1)) / rows, gap, aspectWidth, aspectHeight, columns, rows };
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

/** Bounding box and exact union outline for KLE's primary/secondary rectangles. */
export function keyShape(key) {
  const rectangles = key.rectangles || [{x:0,y:0,width:key.width,height:key.height}];
  if (!rectangles.length || rectangles.some(r => ![r.x,r.y,r.width,r.height].every(Number.isFinite) || r.width <= 0 || r.height <= 0)) throw new Error('Invalid key rectangles');
  const left = Math.min(...rectangles.map(r => r.x)), top = Math.min(...rectangles.map(r => r.y));
  const right = Math.max(...rectangles.map(r => r.x+r.width)), bottom = Math.max(...rectangles.map(r => r.y+r.height));
  const xs = [...new Set(rectangles.flatMap(r => [r.x,r.x+r.width]))].sort((a,b) => a-b);
  const ys = [...new Set(rectangles.flatMap(r => [r.y,r.y+r.height]))].sort((a,b) => a-b);
  const filled = (x,y) => x >= 0 && y >= 0 && x < xs.length-1 && y < ys.length-1
    && rectangles.some(r => (xs[x]+xs[x+1])/2 >= r.x && (xs[x]+xs[x+1])/2 < r.x+r.width && (ys[y]+ys[y+1])/2 >= r.y && (ys[y]+ys[y+1])/2 < r.y+r.height);
  const edges = [];
  for (let y=0;y<ys.length-1;y++) for (let x=0;x<xs.length-1;x++) if (filled(x,y)) {
    const a=[xs[x],ys[y]],b=[xs[x+1],ys[y]],c=[xs[x+1],ys[y+1]],d=[xs[x],ys[y+1]];
    if (!filled(x,y-1)) edges.push([a,b]);
    if (!filled(x+1,y)) edges.push([b,c]);
    if (!filled(x,y+1)) edges.push([c,d]);
    if (!filled(x-1,y)) edges.push([d,a]);
  }
  const same = (a,b) => a[0] === b[0] && a[1] === b[1];
  const first = edges.shift(), outline = [first[0]];
  let end = first[1];
  while (!same(end,outline[0])) {
    outline.push(end);
    const index = edges.findIndex(edge => same(edge[0],end));
    if (index < 0) throw new Error('Disconnected key rectangles');
    end = edges.splice(index,1)[0][1];
  }
  if (edges.length) throw new Error('Key union must be a single outline without holes');
  const width = right-left, height = bottom-top;
  return {left,top,width,height,rectangles,polygon:outline.map(([x,y]) => `${100*(x-left)/width}% ${100*(y-top)/height}%`).join(',')};
}

/** Clip-path and pointer validation share the same rectangle union, not its box. */
export function keyContainsPoint(key,point,box) {
  if (!box || box.width <= 0 || box.height <= 0) return false;
  const shape = keyShape(key);
  const x = shape.left+(point.clientX-box.left)/box.width*shape.width;
  const y = shape.top+(point.clientY-box.top)/box.height*shape.height;
  return shape.rectangles.some(r => x >= r.x && x < r.x+r.width && y >= r.y && y < r.y+r.height);
}
