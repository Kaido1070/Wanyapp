import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';

function parseProject(text) {
  const version = text.match(/^\s*MARKETING_VERSION:\s*['"]?(\d+\.\d+\.\d+)['"]?\s*$/m)?.[1];
  const build = Number(text.match(/^\s*CURRENT_PROJECT_VERSION:\s*['"]?(\d+)['"]?\s*$/m)?.[1]);
  assert.ok(version && Number.isSafeInteger(build) && build > 0,'Set a semantic MARKETING_VERSION and a positive CURRENT_PROJECT_VERSION.');
  return {version,build};
}
function compareVersions(a,b) {
  const av=a.split('.').map(Number), bv=b.split('.').map(Number);
  for(let i=0;i<3;i++) if(av[i]!==bv[i]) return av[i]>bv[i]?1:-1;
  return 0;
}
const development=process.argv.includes('--development');
const current=parseProject(fs.readFileSync('project.yml','utf8'));
const notes=JSON.parse(fs.readFileSync('Wany/Resources/Releases.json','utf8'));
assert.ok(Array.isArray(notes) && notes.length,'Releases.json must include release history.');
assert.equal(notes[0].version,current.version,'The latest release note must match the app version.');
assert.equal(notes[0].build,current.build,'The latest release note must match the app build.');
const versions=new Set();
for(const note of notes) {
  assert.match(note.version,/^\d+\.\d+\.\d+$/);
  assert.ok(!versions.has(note.version),'Duplicate release version.'); versions.add(note.version);
  assert.ok(Number.isSafeInteger(note.build) && note.build>0);
  assert.match(note.date,/^\d{4}-\d{2}-\d{2}$/);
  assert.ok(Array.isArray(note.changes) && note.changes.length && note.changes.every(v=>typeof v==='string' && v.trim()),'Every release must explain its changes.');
}
let base=process.argv.includes('--base') ? process.argv[process.argv.indexOf('--base')+1] : undefined;
if(!base && process.env.GITHUB_EVENT_PATH) {const event=JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH,'utf8'));if(event.before && !/^0+$/.test(event.before))base=event.before;}
if(!base) base='HEAD^';
let previous;
try {previous=parseProject(execFileSync('git',['show',`${base}:project.yml`],{encoding:'utf8',stdio:['ignore','pipe','ignore']}));}
catch(error) {
  // Only a genuine root commit may lack a baseline. Other lookup failures fail closed.
  const parents=execFileSync('git',['rev-list','--parents','-n','1','HEAD'],{encoding:'utf8'}).trim().split(/\s+/);
  if(base!=='HEAD^' || parents.length>1) throw error;
}
if(previous) {
  const versionChange=compareVersions(current.version,previous.version);
  if(development && versionChange===0 && current.build===previous.build) {
    // Logical development commits may retain an unshipped candidate's identity.
  } else {
    assert.ok(versionChange>0,`A release candidate requires a higher version (previous ${previous.version}, current ${current.version}).`);
    assert.ok(current.build>previous.build,`Increment the build number with the version (previous ${previous.build}, current ${current.build}).`);
  }
  const previousNotesText=(()=>{try{return execFileSync('git',['show',`${base}:Wany/Resources/Releases.json`],{encoding:'utf8',stdio:['ignore','pipe','ignore']});}catch{return '[]';}})();
  const previousNotes=JSON.parse(previousNotesText);
  for(const oldNote of previousNotes) assert.deepEqual(notes.find(n=>n.version===oldNote.version),oldNote,'Keep previous release notes unchanged.');
}
console.log(`${development ? 'Development metadata' : 'Release candidate'} verified: Rany ${current.version} (build ${current.build})`);
