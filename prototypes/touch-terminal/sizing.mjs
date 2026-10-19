// Physical pitch is independent of CSS's nominal 96dpi millimetre conversion.
export const UNIT_MM = 19.05;
export function physicalSize(bounds, pixelsPerMM) {
  if (![bounds.width,bounds.height,pixelsPerMM].every(v=>Number.isFinite(v)&&v>0)) throw new RangeError('Invalid physical calibration');
  return {widthMM:bounds.width*UNIT_MM,heightMM:bounds.height*UNIT_MM,widthPx:bounds.width*UNIT_MM*pixelsPerMM,heightPx:bounds.height*UNIT_MM*pixelsPerMM};
}
export function estimatedPixelsPerMM(screenCSSWidth,screenWidthMM) {
  if (!Number.isFinite(screenCSSWidth)||screenCSSWidth<=0||!Number.isFinite(screenWidthMM)||screenWidthMM<100||screenWidthMM>3000) throw new RangeError('屏幕有效显示宽度需在100–3000毫米之间');
  return screenCSSWidth/screenWidthMM;
}
export function rulerCorrection(pixelsPerMM,observedMM) {
  if (!Number.isFinite(pixelsPerMM)||pixelsPerMM<=0||!Number.isFinite(observedMM)||observedMM<20||observedMM>500) throw new RangeError('请填写100毫米参考线的实际测量长度（20–500毫米）');
  return pixelsPerMM*100/observedMM;
}
export function displayFingerprint(screenCSSWidth,screenCSSHeight,dpr) {return [screenCSSWidth,screenCSSHeight,dpr].join(':');}
