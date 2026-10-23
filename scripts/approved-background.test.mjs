import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const approved=readFileSync(new URL('../Tests/Fixtures/rany-gold-smooth-transition.html',import.meta.url),'utf8');
const bundled=readFileSync(new URL('../Wany/Resources/RanyApprovedBackground.html',import.meta.url),'utf8');
test('the app bundles the exact approved drawing, without replacing page motion or final color treatment',()=>{
 const drawing=approved.slice(approved.indexOf('const W=390'),approved.indexOf('function tick(now)'));
 const embedded=bundled.split('// BEGIN UNMODIFIED APPROVED DRAWING\n')[1].split('// END UNMODIFIED APPROVED DRAWING')[0];
 assert.equal(embedded,drawing);
});
test('the background has no interface lettering, preview controls or external image requests',()=>{
 assert.ok(!/<button|<input|<a\s|\bREAD\b|\bANYTIME\b|https?:\/\//i.test(bundled));
 assert.ok(bundled.includes("img-src data:"));
 assert.ok(bundled.includes('openingStarts'));
 assert.ok(bundled.includes('token!==mine'));
});

test('the opening clock stays frozen until native typography acknowledges preparation',async()=>{
 const events=[],draws=[],frames=new Map(); let clock=1000,next=0;
 const context={Math,Promise,Error,queueMicrotask,performance:{now:()=>clock},
  window:{webkit:{messageHandlers:{ranyBackground:{postMessage:message=>events.push(message)}}}},
  requestAnimationFrame:callback=>{frames.set(++next,callback);return next},cancelAnimationFrame:id=>frames.delete(id),
  Image:class { set src(value){this.url=value;queueMicrotask(()=>this.onload())} },draws};
 const lifecycle=bundled.split('// Native lifecycle and local image transport only; drawing above is unchanged.')[1].split('})();')[0];
 vm.runInNewContext(`(()=>{let playing=false,ready=false,elapsed=0,anchor=0,raf=0,imgs=[],inkImages=[];
 const W=390,H=780,ctx={setTransform(){},fillRect(){}};
 function prepareInk(){} function draw(time){draws.push(time)}
 ${lifecycle} })();`,context);
 const api=context.window.RanyBackground;
 await api.configure({token:'owner-a',images:['local-fixture'],active:true,opening:true,titleReady:false});
 assert.equal(api.state().ready,true);assert.equal(api.state().started,false);
 assert.deepEqual(draws,[0]);assert.equal(frames.size,0);
 clock+=1200;api.setActive(true);
 assert.equal(api.state().time,0);assert.equal(api.state().openingStarts,0);
 api.setTypographyReady(true);assert.equal(api.state().openingStarts,1);
 // A queued first RAF can be delayed by cold WebKit/compositor startup.
 clock+=1200;const [id,tick]=frames.entries().next().value;frames.delete(id);tick(clock);
 assert.equal(api.state().time,0,'Waiting for the first actual frame must not consume any opening phase.');
 clock+=16;const [nextId,nextTick]=frames.entries().next().value;frames.delete(nextId);nextTick(clock);
 assert.ok(Math.abs(api.state().time-0.016)<0.001);
 assert.equal(events.filter(x=>x.event==='started').length,1);
 api.setTypographyReady(true);api.setActive(false);api.setActive(true);
 assert.equal(api.state().openingStarts,1,'Readiness updates and foreground return must not restart the opening.');
});
