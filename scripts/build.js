import {build} from 'esbuild';import {mkdir,cp,writeFile,readFile,stat} from 'node:fs/promises';import {resolve} from 'node:path';
await mkdir('dist',{recursive:true});await cp('public','dist',{recursive:true});
await build({entryPoints:['src/app.js'],outfile:'dist/app.js',bundle:true,format:'esm',target:['safari16.4','chrome110'],minify:true});
await build({entryPoints:['worker/index.js'],outfile:'dist/_worker.js',bundle:true,format:'esm',platform:'node',target:'es2022',external:['node:*'],banner:{js:"import {createRequire} from 'node:module'; const require=createRequire('/worker.js');"},minify:true});
await writeFile('dist/_routes.json',JSON.stringify({version:1,include:['/api/*'],exclude:[]}));
const files=['assets/main-bg-forever.png','assets/relieve-bg.png','assets/cell.glb','assets/smartwatch.glb','assets/hammer.glb','assets/gold_star.glb','assets/cube_calendar.glb','assets/first-page.png','assets/second-page.png','assets/third-page.png','assets/fourth-page.png','assets/fifth-page.png'];for(const f of files)if(!(await stat('dist/'+f)).size)throw Error('Missing asset: '+f);
const app=await readFile('dist/app.js','utf8');if(/sb_secret_[A-Za-z0-9_-]{20,}/.test(app))throw Error('Private key in browser bundle');console.log('Build passed: app, website, worker, and all required assets.');
