// English is a page-local view; canonical CN encoding remains case sensitive.
export function viewKey(key, english=false) {
  if (!english) return key;
  const overlay = key.english;
  if (!overlay) throw new Error('Missing English layout');
  return {...key,...overlay,shiftAction:overlay.shiftAction,editAction:overlay.editAction,
    yinyuanIds:[],baseYinyuanIds:[],shiftYinyuanIds:[],displayLabels:overlay.labels};
}

export function useEnglishLayout(inputMode, preference) {
  return inputMode === 'english' && preference === 'english';
}
