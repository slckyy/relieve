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
  return new GLTFLoader().parseAsync(data, new URL('./', new URL(asset, import.meta.url)).href);
}
export function releaseLumiDownloads() { buffers.clear(); }
