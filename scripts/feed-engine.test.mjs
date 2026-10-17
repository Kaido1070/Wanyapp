import {test} from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
const code=fs.readFileSync(new URL('../Wany/Resources/FeedEngine.js',import.meta.url),'utf8');
function context(){ const c=vm.createContext({nativeTimer(){},nativeProgress(){},nativeResult(){},nativeRequest(){}});vm.runInContext(code,c);return c; }
const item=(key,source='teamx')=>({key,source,sourceId:key,slug:'test-story',title:'Test Story',type:'manhwa',cover:'cover',url:'https://example.com',genres:['action','fantasy']});
test('same website ranking excludes unrelated candidates for established taste',()=>{
 const c=context();c.signals=[{item:item('tx:seed'),weight:6,kind:'favorite'}];c.candidates=[{item:item('tx:match'),sourceKeys:['tx:match'],popularity:0,freshness:0},{item:{...item('tx:unrelated'),type:'manga',genres:['romance']},sourceKeys:['tx:unrelated'],popularity:1,freshness:1}];
 const r=vm.runInContext('rankRecommendations(candidates,signals)',c);assert.equal(r[0].item.key,'tx:match');assert.equal(r[0].algorithmVersion,'10.5.2');assert.ok(r[0].reason.includes('Test Story'));
});
test('source merge keeps source identities while grouping same story',()=>{const c=context();c.items=[item('tx:one'),item('aq:two','3asq')];const r=vm.runInContext('mergeSourceItems(items)',c);assert.equal(r.length,1);assert.equal(r[0].items.length,2);});
test('bridge preserves chapter identity in batched read-state requests',async()=>{
 const c=context();const sent=[];c.nativeRequest=(id,path,method,body)=>{sent.push(JSON.parse(body));c.settleRequest(id,JSON.stringify({read:JSON.parse(body).chapters}), '');};
 c.pairs=Array.from({length:85},(_,i)=>({mangaId:'tx:one',chapter:i+0.5}));
 const result=await vm.runInContext('userDataService.getReadChapterPairs(pairs)',c);assert.equal(result.length,85);assert.deepEqual(sent.map(x=>x.chapters.length),[40,40,5]);assert.equal(result[0].chapter,0.5);
});
test('FYP and New entrypoints invoke native error callback rather than hang',async()=>{
 const c=context();let result;c.nativeRequest=(id)=>c.settleRequest(id,'','offline');c.nativeResult=(id,data,error)=>{result={id,data,error};};
 await vm.runInContext('runFeed("new",{},"user",1,"run")',c);assert.equal(result.id,'run');assert.equal(result.error,'offline');
});
test('discovery applies website type, status, genre and source filters together',()=>{
 const c=context();c.items=[{...item('tx:a'),status:'ongoing'},{...item('aq:b','3asq'),status:'completed'},{...item('tx:c'),type:'manga',status:'ongoing',genres:['romance']}];
 c.filter={source:'teamx',type:'manhwa',status:'ongoing',genres:['action']};
 const r=vm.runInContext('catalogGroups(items,filter)',c);assert.equal(r.length,1);assert.equal(r[0].primary.key,'tx:a');
});
test('source grouping separates numbered works and duplicate same-source titles',()=>{
 const c=context();c.items=[{...item('tx:a'),title:'Legend of the Northern Blade 1',slug:'legend-blade-1'},{...item('aq:b','3asq'),title:'Legend of the Northern Blade 2',slug:'legend-blade-2'}];
 assert.equal(vm.runInContext('mergeSourceItems(items).length',c),2);
 c.items=[item('tx:first'),item('tx:second')];assert.equal(vm.runInContext('mergeSourceItems(items).length',c),2);
});
