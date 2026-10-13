const pendingRequests = new Map(); let requestSequence = 0;
function request(path, method='GET', body=null) {
 return new Promise((resolve,reject)=>{const id=String(++requestSequence);pendingRequests.set(id,{resolve,reject});nativeRequest(id,path,method,JSON.stringify(body));});
}
function settleRequest(id,text,error) { const p=pendingRequests.get(id);if(!p)return;pendingRequests.delete(id);if(error)p.reject(new Error(error));else {try{p.resolve(JSON.parse(text));}catch(e){p.reject(e);}} }
const memoryStorage=new Map();
const sessionStorage={getItem:k=>memoryStorage.get(k)||null,setItem:(k,v)=>memoryStorage.set(k,v)};
let timerSequence=0;const timers=new Map();
function setTimeout(fn,ms) {const id=String(++timerSequence);timers.set(id,fn);nativeTimer(id,ms);return id;}
function clearTimeout(id) {timers.delete(id);}
function fireTimer(id) {const f=timers.get(id);timers.delete(id);if(f)f();}
function query(path,values) {return '/api/source/'+path+'?'+Object.entries(values).filter(([,v])=>v!==undefined).map(([k,v])=>encodeURIComponent(k)+'='+encodeURIComponent(v)).join('&');}
const sourceService={
 isSourceKey:key=>Boolean(key&&/^(mt|tx|aq|sz|xs|ml|az):/.test(key)),
 recent:(source,page=1)=>request(query('recent',{source,page})),
 latest:(source,page=1)=>request(query('latest',{source,page})),
 popular:(source,page=1)=>request(query('popular',{source,page})),
 releaseHistory:chapters=>request(query('release-history',{chapters:[...new Set(chapters)].filter(Number.isFinite).slice(0,80).join(',')})),
 resolve:async keys=>keys.length?(await request(query('resolve',{keys:keys.join(',')}))).items:[],
 getSeries:async key=>(await request(query('series',{key}))).item,
};
const userDataService={
 getPersonalizationState:()=>request('/api/personalization-state'),
 getLists:async()=>(await request('/api/lists')).lists||[],
 getList:async id=>{const r=await request('/api/lists/'+encodeURIComponent(id));return {...r.list,items:r.items||[]};},
 getReadChapterPairs:async pairs=>{const out=[];for(let i=0;i<pairs.length;i+=40){const r=await request('/api/personalization-state','POST',{chapters:pairs.slice(i,i+40)});out.push(...(r.read||[]));}return out;}
};
