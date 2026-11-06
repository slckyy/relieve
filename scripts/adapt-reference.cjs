const fs=require('node:fs');
for(const file of ['lumi-home.js','lumi-viewer.js']){
 let s=fs.readFileSync('../sanction/dist/'+file,'utf8');
 s=s.replaceAll("model.getObjectByName('LUMI_CHARACTER')","model");
 s=s.replaceAll("new THREE.Color().fromArray(gltf.parser.json.asset.extras.atmosphere_key_linear)","new THREE.Color(0xffffff)");
 s=s.replaceAll('0xf1eff4','0xffffff').replaceAll('0x49494d','0x777777').replaceAll('0xdedee8','0xffffff');
 s=s.replaceAll('), 19)', '), 6)');
 if(file==='lumi-home.js'){
  s=s.replace('const appearance = appearances[item.id];',"const appearance = { badge:item.accent, phase:i * 1.1, spin:.14, yaw:0, rhythm:i };");
  s=s.replace("model.position.sub(new THREE.Box3()", "model.scale.multiplyScalar(.12 / new THREE.Box3().setFromObject(model).getSize(new THREE.Vector3()).length()); scene.updateMatrixWorld(true);\n    model.position.sub(new THREE.Box3()");
 } else {
  s=s.replace('model.updateMatrixWorld(true);',"model.scale.multiplyScalar(.12 / new THREE.Box3().setFromObject(model).getSize(new THREE.Vector3()).length());\n    model.updateMatrixWorld(true);");
 }
 fs.writeFileSync('public/'+file,s);
}
