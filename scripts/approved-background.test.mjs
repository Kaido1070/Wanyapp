import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
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
