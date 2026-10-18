const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
async function main(){
const {createCanvas,loadImage}=require('@napi-rs/canvas');
const root=path.resolve(__dirname,'..');
const source=fs.readFileSync(root+'/Tests/Fixtures/rany-gold-smooth-transition.html','utf8');
const imgs=[];for(let i=1;i<=14;i++){const image=await loadImage(root+'/Wany/Assets.xcassets/RanyDefault'+i+'.imageset/cover.jpg');if(image.naturalWidth===undefined)Object.defineProperty(image,'naturalWidth',{value:image.width});if(image.complete===undefined)Object.defineProperty(image,'complete',{value:true});imgs.push(image);}
const canvas=createCanvas(780,1560),ctx=canvas.getContext('2d');ctx.scale(2,2);
const scope={imgs,ctx,mode:0,document:{createElement:()=>createCanvas(1,1)}};vm.createContext(scope);
vm.runInContext(source.slice(source.indexOf('const W=390'),source.indexOf('function tick(now)'))+'\nprepareInk();',scope);
for(const t of [.3,.8,1.08,1.65,2.4,3.1,4.3]){vm.runInContext('draw('+t+');',scope);const out=createCanvas(390,780);out.getContext('2d').drawImage(canvas,0,0,390,780);fs.writeFileSync(root+'/Tests/Fixtures/approved-'+String(t).replace('.','_')+'.png',out.toBuffer('image/png'));}

}
main().catch(error=>{console.error(error);process.exitCode=1});
