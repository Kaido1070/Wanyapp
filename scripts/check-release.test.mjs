import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync, spawnSync} from 'node:child_process';
const checker=fs.readFileSync(new URL('./check-release.mjs',import.meta.url),'utf8');
function scenario(run) {
  const cwd=fs.mkdtempSync(path.join(os.tmpdir(),'rany-release-'));
  const git=(...args)=>execFileSync('git',args,{cwd,stdio:'pipe'});
  let notes=[{version:'1.3.29',build:57,date:'2026-10-17',changes:['مرجع التجربة']}];
  const write=(version='1.3.29',build=57,history=notes)=>{
    fs.writeFileSync(path.join(cwd,'project.yml'),`MARKETING_VERSION: ${version}\nCURRENT_PROJECT_VERSION: ${build}\n`);
    fs.writeFileSync(path.join(cwd,'Wany/Resources/Releases.json'),JSON.stringify(history));
  };
  try {
    fs.mkdirSync(path.join(cwd,'Wany/Resources'),{recursive:true});
    fs.writeFileSync(path.join(cwd,'check-release.mjs'),checker);
    git('init','-q');git('config','user.email','tests@example.invalid');git('config','user.name','Release tests');
    write();git('add','.');git('commit','-qm','baseline');
    const check=(...args)=>spawnSync(process.execPath,['check-release.mjs',...(args.includes('--base')?[]:['--base','HEAD']),...args],{cwd,encoding:'utf8',env:{...process.env,GITHUB_EVENT_PATH:''}}).status;
    run({write,notes,check});
  } finally { fs.rmSync(cwd,{recursive:true,force:true}); }
}
test('logical development commits retain version; release candidates still require a bump',()=>scenario(({check})=>{
  assert.equal(check('--development'),0);assert.notEqual(check(),0);
}));
test('both version and build must advance together, without rollback',()=>scenario(({write,notes,check})=>{
  for(const [version,build] of [['1.3.28',56],['1.3.29',58],['1.3.30',57]]) {
    write(version,build,[{...notes[0],version,build}]);assert.notEqual(check('--development'),0);
  }
}));
test('a new candidate preserves previous notes and passes the strict gate',()=>scenario(({write,notes,check})=>{
  write('1.3.30',58,[{...notes[0],version:'1.3.30',build:58},...notes]);assert.equal(check(),0);
}));
test('same-version development cannot rewrite previous release notes',()=>scenario(({write,notes,check})=>{
  write('1.3.29',57,[{...notes[0],changes:['Changed historical entry']}]);assert.notEqual(check('--development'),0);
}));
test('metadata mismatch and missing baseline fail closed',()=>scenario(({write,check})=>{
  write('1.3.30',58);assert.notEqual(check('--development'),0);write();assert.notEqual(check('--development','--base','missing-ref'),0);
}));
