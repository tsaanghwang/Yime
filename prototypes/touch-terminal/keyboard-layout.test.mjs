import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {viewKey,useEnglishLayout} from './keyboard-layout.mjs';
import {virtualKeyAction,protocolAction} from './input.mjs';
const layout=JSON.parse(readFileSync(new URL('./data/physical-layout.json',import.meta.url),'utf8'));

test('English view preserves geometry, clears inherited CN layers, and never uses color as enablement',()=>{
  for(const base of layout.keys){
    const en=viewKey(base,true);
    for(const field of ['id','x','y','width','height','rectangles','color'])assert.deepEqual(en[field],base[field]);
    assert.deepEqual(en.yinyuanIds,[]);
    if(!base.english.shiftAction)assert.equal(en.shiftAction,undefined);
    assert.equal(Boolean(viewKey({...base,color:'#000000'},true).disabled),Boolean(en.disabled));
  }
  assert.equal(layout.keys.filter(k=>viewKey(k,true).disabled).length,23);
});

test('all English letters output base lowercase and Shift uppercase',()=>{
  for(const char of 'abcdefghijklmnopqrstuvwxyz'){
    const key=layout.keys.map(k=>viewKey(k,true)).find(k=>k.action.ascii===char);
    assert.ok(key,char);
    assert.equal(virtualKeyAction(key,false).action.ascii,char);
    assert.equal(virtualKeyAction(key,true).action.ascii,char.toUpperCase());
  }
});

test('a retained English preference applies only in English mode',()=>{
  assert.equal(useEnglishLayout('chinese','english'),false);
  assert.equal(useEnglishLayout('english','english'),true);
  assert.equal(useEnglishLayout('english','original'),false);
});

test('literal entrance switch never bypasses ID-bearing coding layers',()=>{
  for(const key of layout.keys)for(const [field,shifted] of [['baseYinyuanIds',false],['shiftYinyuanIds',true]]){
    if((key[field]||[]).length)assert.equal(virtualKeyAction(key,shifted,true,true).action.type,'input');
  }
  const key=layout.keys.find(k=>k.shiftAction?.literalEntry);
  assert.equal(virtualKeyAction(key,true,true,false).action.type,'input');
  assert.equal(virtualKeyAction(key,true,true,true).action.type,'symbol');
  for(const ascii of '·、—×√÷')assert.deepEqual(protocolAction({type:'symbol',ascii},{}),{type:'symbol',code:ascii});
  for(const ascii of ['你','a','ab','',String.fromCharCode(0)])assert.throws(()=>protocolAction({type:'symbol',ascii},{}));
});
