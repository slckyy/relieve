import { GLTFLoader } from './vendor/three-gltf.js?v=home-1';

// Home and manager viewers share each download, while owning their GPU resources.
const buffers = new Map();
export function preloadLumi(asset) {
  const url = new URL(asset, import.meta.url).href;
  if (!buffers.has(url)) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 60000);
    const request = fetch(url, { signal: controller.signal }).then(response => {
      if (!response.ok) throw new Error(`LUMI download failed: ${response.status}`);
      return response.arrayBuffer();
    }).catch(error => { buffers.delete(url); throw error; }).finally(() => clearTimeout(timeout));
    buffers.set(url, request);
  }
  return buffers.get(url);
}
export async function loadLumi(asset) {
  const data = await preloadLumi(asset);
  const gltf = await new GLTFLoader().parseAsync(data, new URL('./', new URL(asset, import.meta.url)).href);
  // Asset-local poses are shared by Home and the interactive page viewers.
  if (/cell\.glb(?:[?#]|$)/.test(asset)) {
    gltf.scene.rotation.set(-.12, -.30, -.20, 'ZYX');
    gltf.scene.traverse(object => {
      for (const material of [].concat(object.material || [])) {
        if (material.name !== 'COLOUR_Black_Screen') continue;
        material.color.set(0x000000);
        material.emissive.set(0x000000);
        material.emissiveIntensity = 0;
        material.envMapIntensity = 0;
        material.roughness = .85;
      }
    });
  } else if (/hammer\.glb(?:[?#]|$)/.test(asset)) {
    gltf.scene.rotation.set(1.10, .20, -1.15, 'ZYX');
  }
  return gltf;
}
export function releaseLumiDownloads() { buffers.clear(); }
