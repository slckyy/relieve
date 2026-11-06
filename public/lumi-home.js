import * as THREE from './vendor/three-gltf.js?v=home-1';
import { loadLumi } from './lumi-assets.js?v=startup-1';

// Three live GLBs, one WebGL context. Each whole character is composited with
// one opacity so ghosting never exposes its hidden interior construction.
export function mountLumiHome(panel, items, onSelect, { paused = false, onPrepared = () => {} } = {}) {
  const host = panel.querySelector('.home-selector');
  const backgroundTrack = panel.querySelector('.home-background-track');
  const abort = new AbortController();
  const on = (target, type, fn, options = {}) => target.addEventListener(type, fn, { ...options, signal: abort.signal });
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const appearances = {
    call: { badge: '#F28B96', phase: 1.1, spin: .16, yaw: .35, rhythm: 0 },
    clients: { badge: '#86A5FF', phase: 0, spin: .14, yaw: 0, rhythm: 2 },
    events: { badge: '#78D9B5', phase: 4.2, spin: -.17, yaw: .28, rhythm: 3 }
  };
  let selected = 0, position = 0, target = 0, pointer = null, wheelAt = 0;
  // Keep the backdrop stationary while the models move.
  backgroundTrack.style.transform = 'none';
  let frame = 0, last = 0, elapsed = 0, disposed = false, renderReady = false, width = 1, height = 1;
  const entries = items.map((item, i) => {
    const appearance = { badge:item.accent, phase:i * 1.1, spin:.14, yaw:0, rhythm:i };
    const button = document.createElement('button');
    button.type = 'button'; button.className = 'home-lumi-label edition-label';
    button.id = `home-lumi-${item.id}`; button.setAttribute('role', 'option');
    button.setAttribute('aria-label', `${item.color} ${item.lumi}, ${item.id.toUpperCase()}`);
    button.style.setProperty('--page-accent', appearance.badge);
    const badge = document.createElement('span'); badge.className = 'color-badge'; badge.textContent = item.color;
    const title = document.createElement('span'); title.textContent = item.lumi;
    button.append(badge, title); host.append(button);
    on(button, 'click', () => select(i));
    return { item, button, i, appearance, weight: i === 0 ? 1 : 0, scene: null, lights: [], meshes: [] };
  });
  function announce() {
    for (const e of entries) { e.button.setAttribute('aria-selected', String(e.i === selected)); e.button.tabIndex = e.i === selected ? 0 : -1; }
    onSelect(selected);
  }
  const clamp = n => Math.max(0, Math.min(items.length - 1, n));
  function select(index, instant = false) {
    selected = Math.round(clamp(index)); target = selected;
    if (instant || motion.matches) position = target;
    announce(); wake();
  }
  announce();
  on(host, 'keydown', event => {
    const next = { ArrowLeft: selected - 1, ArrowRight: selected + 1, Home: 0, End: items.length - 1 }[event.key];
    if (next === undefined) return;
    event.preventDefault(); select(next); entries[selected].button.focus({ preventScroll: true });
  });
  let renderer;
  try { renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, powerPreference: 'high-performance' }); }
  catch (error) {
    host.classList.add('home-selector-fallback');
    console.warn('LUMI home WebGL unavailable', error);
    return { select, ready: Promise.reject(error), dispose() { disposed = true; abort.abort(); } };
  }
  renderer.setClearColor(0, 0); renderer.autoClear = false;
  renderer.outputColorSpace = THREE.SRGBColorSpace; renderer.toneMapping = THREE.NeutralToneMapping; renderer.toneMappingExposure = 1;
  renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFShadowMap;
  renderer.domElement.setAttribute('aria-hidden', 'true'); host.prepend(renderer.domElement);
  const camera = new THREE.PerspectiveCamera(32, 1, .005, 2); camera.position.z = .32;
  const renderTarget = new THREE.WebGLRenderTarget(1, 1, {
    type: renderer.extensions.has('EXT_color_buffer_float') ? THREE.HalfFloatType : THREE.UnsignedByteType,
    samples: 2, depthBuffer: true
  });
  const composite = new THREE.Scene(), quadCamera = new THREE.Camera();
  const quadMaterial = new THREE.ShaderMaterial({
    uniforms: { image: { value: renderTarget.texture }, opacity: { value: 1 } },
    vertexShader: 'varying vec2 vUv; void main(){vUv=uv;gl_Position=vec4(position.xy,0.0,1.0);}',
    fragmentShader: `uniform sampler2D image; uniform float opacity; varying vec2 vUv;
      void main(){gl_FragColor=texture2D(image,vUv);gl_FragColor.a*=opacity;
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
      }`,
    transparent: true, depthWrite: false, depthTest: false
  });
  const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), quadMaterial); composite.add(quad);
  // Visible light haze under the selected model, paired with its real underlight.
  // It stays in the home renderer; no floor or glow geometry enters the GLBs.
  const glowScene = new THREE.Scene();
  const glowMaterial = new THREE.ShaderMaterial({
    uniforms: { center: { value: new THREE.Vector2() }, spread: { value: new THREE.Vector2() },
      color: { value: new THREE.Color() }, power: { value: 0 } },
    vertexShader: quadMaterial.vertexShader,
    fragmentShader: `uniform vec2 center; uniform vec2 spread; uniform vec3 color; uniform float power; varying vec2 vUv;
      void main(){
        vec2 p=(vUv-center)/spread;
        float haze=exp(-dot(p,p)*2.5);
        float core=exp(-p.x*p.x*5.0-p.y*p.y*28.0);
        gl_FragColor=vec4(color*(0.7+0.3*core),min(0.9,(0.55*haze+0.65*core)*power));
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }`,
    transparent: true, depthWrite: false, depthTest: false
  });
  glowScene.add(new THREE.Mesh(quad.geometry, glowMaterial));
  const pmrem = new THREE.PMREMGenerator(renderer);
  function makeEnvironment(sky, powered) {
    const w = 128, h = 64, data = new Float32Array(w * h * 4);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const up = -Math.cos(Math.PI * (y + .5) / h), sun = powered ? Math.pow(Math.max(0, -up), 18) * 8 : 0;
      const base = .35 + .55 * Math.max(0, up), offset = (y * w + x) * 4;
      data[offset] = base * (.72 + .28 * sky.r) + sun * sky.r;
      data[offset + 1] = base * (.72 + .28 * sky.g) + sun * sky.g;
      data[offset + 2] = base * (.72 + .28 * sky.b) + sun * sky.b; data[offset + 3] = 1;
    }
    const texture = new THREE.DataTexture(data, w, h, THREE.RGBAFormat, THREE.FloatType);
    texture.mapping = THREE.EquirectangularReflectionMapping; texture.needsUpdate = true;
    const env = pmrem.fromEquirectangular(texture); texture.dispose(); return env;
  }
  const neutralEnvironment = makeEnvironment(new THREE.Color(0xffffff), false);
  const scratch = new THREE.Vector3(), labelPoint = new THREE.Vector3(), ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
  function stop() { cancelAnimationFrame(frame); frame = 0; last = 0; }
  function wake() { if (!paused && renderReady && !disposed && !panel.hidden && !document.hidden && !frame) frame = requestAnimationFrame(draw); }
  function resize() {
    const rect = host.getBoundingClientRect(); if (!rect.width || !rect.height) return;
    width = rect.width; height = rect.height;
    const dpr = Math.min(devicePixelRatio || 1, 1.5);
    renderer.setPixelRatio(dpr); renderer.setSize(width, height, false); renderTarget.setSize(Math.round(width * dpr), Math.round(height * dpr));
    camera.aspect = width / height; camera.updateProjectionMatrix(); camera.updateMatrixWorld(); wake();
  }
  const resizeObserver = new ResizeObserver(resize); resizeObserver.observe(host);
  const panelObserver = new MutationObserver(() => { if (panel.hidden) { pointer = null; stop(); } else { resize(); wake(); } });
  panelObserver.observe(panel, { attributes: true, attributeFilter: ['hidden'] });
  on(document, 'visibilitychange', () => document.hidden ? stop() : wake());
  on(motion, 'change', wake);
  on(window, 'pagehide', e => e.persisted ? stop() : dispose()); on(window, 'pageshow', wake);
  on(renderer.domElement, 'webglcontextlost', e => { e.preventDefault(); renderReady = false; stop(); });
  on(renderer.domElement, 'webglcontextrestored', () => { renderReady = true; wake(); });

  on(host, 'pointerdown', event => {
    if (!event.isPrimary || (event.pointerType === 'mouse' && event.button !== 0) || event.target.closest('button')) return;
    pointer = { id: event.pointerId, x: event.clientX, start: position, dragged: false };
    host.setPointerCapture(event.pointerId);
  });
  on(host, 'pointermove', event => {
    if (!pointer || pointer.id !== event.pointerId) return;
    const dx = event.clientX - pointer.x;
    if (Math.abs(dx) > 8) { pointer.dragged = true; host.classList.add('is-dragging'); }
    if (!pointer.dragged) return;
    event.preventDefault(); target = clamp(pointer.start - dx / (width * .36)); position = target;
    const next = Math.round(target); if (selected !== next) { selected = next; announce(); } wake();
  });
  function release(event) {
    if (!pointer || pointer.id !== event.pointerId) return;
    const dragged = pointer.dragged; pointer = null; host.classList.remove('is-dragging');
    if (host.hasPointerCapture(event.pointerId)) host.releasePointerCapture(event.pointerId);
    if (!dragged && event.type === 'pointerup') {
      const rect = host.getBoundingClientRect(); ndc.set((event.clientX - rect.left) / width * 2 - 1, 1 - (event.clientY - rect.top) / height * 2);
      ray.setFromCamera(ndc, camera);
      const hits = entries.flatMap(e => { e.scene?.updateMatrixWorld(true); return ray.intersectObjects(e.meshes, false).map(hit => ({ i: e.i, distance: hit.distance })); });
      hits.sort((a, b) => a.distance - b.distance); if (hits.length) selected = hits[0].i;
    }
    select(selected);
  }
  on(host, 'pointerup', release); on(host, 'pointercancel', release); on(host, 'lostpointercapture', release);
  on(host, 'wheel', event => {
    const delta = Math.abs(event.deltaX) > Math.abs(event.deltaY) ? event.deltaX : event.deltaY;
    if (!delta) return;
    event.preventDefault(); const now = performance.now();
    if (now - wheelAt > 220 && Math.abs(delta) > 8) { wheelAt = now; select(selected + Math.sign(delta)); }
  }, { passive: false });

  function draw(ms) {
    frame = 0; if (disposed || panel.hidden || document.hidden) return;
    const dt = last ? Math.min((ms - last) / 1000, .1) : 1 / 60; last = ms; elapsed += dt;
    if (!pointer) position += (target - position) * (motion.matches ? 1 : 1 - Math.exp(-dt * 13));
    if (Math.abs(target - position) < .0001) position = target;
    // Render the models at their fractional drag/settling positions.
    renderer.setRenderTarget(null); renderer.clear();
    const ordered = [...entries].sort((a, b) => Math.abs(b.i - position) - Math.abs(a.i - position));
    for (const e of ordered) {
      const d = e.i - position, distance = Math.abs(d), depth = -.10 * distance, scale = 1 / (1 + .22 * distance);
      const projectedX = Math.sign(d) * .93 * (1 - Math.exp(-distance * 1.05));
      const x = projectedX * (.32 - depth) * Math.tan(16 * Math.PI / 180) * camera.aspect;
      e.weight += ((e.i === selected ? 1 : 0) - e.weight) * (motion.matches ? 1 : 1 - Math.exp(-dt * 14));
      if (e.weight < .0001) e.weight = 0; if (e.weight > .9999) e.weight = 1;
      const ghost = .28 / (1 + distance * .4), opacity = ghost + (1 - ghost) * e.weight;
      // Keep each title close beneath its own LUMI as the lineup moves in depth.
      labelPoint.set(x, .008 - .078 * scale, depth).project(camera);
      const labelScale = Math.max(.46, scale * .32 / (.32 - depth));
      e.button.style.left = `${(labelPoint.x * .5 + .5) * width}px`; e.button.style.top = `${(-labelPoint.y * .5 + .5) * height}px`;
      e.button.style.transform = `translate(-50%, -50%) scale(${labelScale})`; e.button.style.opacity = String(opacity);
      e.button.style.zIndex = String(e.i === selected ? 30 : 10 - Math.round(distance * 2));
      if (!e.scene) continue;
      const { phase, spin, yaw, rhythm } = e.appearance, moving = motion.matches ? 0 : 1;
      e.placement.position.set(x, .008 + moving * .0016 * Math.sin(elapsed * (3.1 + rhythm * .31) + phase), depth);
      e.placement.scale.setScalar(e.normalization * scale);
      e.assembly.rotation.set(moving * .075 * Math.sin(elapsed * (.7 + rhythm * .11) + phase),
        moving * (elapsed * spin + yaw),
        moving * .045 * Math.sin(elapsed * (.8 + rhythm * .13) + phase));
      const s = e.normalization * scale;
      e.key.position.copy(e.placement.position).add(scratch.set(-.018, -.22, .065).multiplyScalar(s)); e.key.target.position.copy(e.placement.position);
      e.key.intensity = 19 * e.weight; e.key.shadow.autoUpdate = e.weight > .01;
      e.key.shadow.needsUpdate = !e.key.shadow.map || e.weight > .01;
      e.fill.position.copy(e.placement.position).add(scratch.set(.07, .015, .16).multiplyScalar(s));
      e.scene.environment = e.weight > .5 ? e.environment.texture : neutralEnvironment.texture;
      e.scene.environmentIntensity = .75 + .35 * e.weight;
      for (const light of e.lights) light.intensity = light.userData.power * s * s * e.weight;
      if (e.i === selected) {
        scratch.set(x, .008 - .063 * scale, depth).project(camera);
        const viewHeight = 2 * (.32 - depth) * Math.tan(16 * Math.PI / 180);
        glowMaterial.uniforms.center.value.set(scratch.x * .5 + .5, scratch.y * .5 + .5);
        glowMaterial.uniforms.spread.value.set(.062 * scale / (viewHeight * camera.aspect), .018 * scale / viewHeight);
        glowMaterial.uniforms.color.value.copy(e.glowColor);
        glowMaterial.uniforms.power.value = e.weight;
        renderer.setRenderTarget(null); renderer.render(glowScene, quadCamera);
      }
      renderer.setRenderTarget(renderTarget); renderer.clear(); renderer.render(e.scene, camera);
      renderer.setRenderTarget(null); quadMaterial.uniforms.opacity.value = opacity; renderer.render(composite, quadCamera);
    }
    host.dataset.homeSelection = items[selected].id;
    if (!motion.matches || position !== target || entries.some(e => e.weight !== (e.i === selected ? 1 : 0))) wake();
  }

  async function load(e) {
    const gltf = await loadLumi(e.item.asset);
    if (disposed) { freeModel(gltf.scene); return; }
    const scene = e.scene = new THREE.Scene(), model = e.model = gltf.scene;
    const placement = e.placement = new THREE.Group(), assembly = e.assembly = new THREE.Group();
    scene.add(placement); placement.add(assembly); assembly.add(model); scene.updateMatrixWorld(true);
    model.scale.multiplyScalar(.12 / new THREE.Box3().setFromObject(model).getSize(new THREE.Vector3()).length()); scene.updateMatrixWorld(true);
    model.position.sub(new THREE.Box3().setFromObject(model).getCenter(new THREE.Vector3())); scene.updateMatrixWorld(true);
    let radius = 0;
    model.traverse(o => {
      if (!o.isMesh) return; e.meshes.push(o); o.castShadow = true; o.receiveShadow = true;
      const a = o.geometry.attributes.position;
      for (let i = 0; i < a.count; i++) radius = Math.max(radius, scratch.fromBufferAttribute(a, i).applyMatrix4(o.matrixWorld).length());
      for (const material of [].concat(o.material)) {
        for (const texture of [material.normalMap, material.roughnessMap]) if (texture) texture.anisotropy = Math.min(4, renderer.capabilities.getMaxAnisotropy());
        if (material.transmission && !renderer.extensions.has('EXT_color_buffer_float')) material.transmission = 0;
      }
    });
    e.normalization = .065 / radius;
    const sky = new THREE.Color(0xffffff);
    e.glowColor = sky.clone();
    e.environment = makeEnvironment(sky, true);
    e.key = new THREE.DirectionalLight(sky.clone().lerp(new THREE.Color(0xffffff), .38), 6); e.key.castShadow = true;
    e.key.shadow.mapSize.set(512, 512); Object.assign(e.key.shadow.camera, { left: -.14, right: .14, top: .14, bottom: -.14, near: .005, far: 1 });
    e.key.shadow.bias = -.00003; e.key.shadow.normalBias = .00009; e.key.shadow.radius = 3;
    scene.add(e.key, e.key.target, new THREE.HemisphereLight(sky.clone().lerp(new THREE.Color(0xffffff), .8), 0x777777, 1.8));
    e.fill = new THREE.DirectionalLight(0xffffff, 1); scene.add(e.fill);
    for (const mesh of e.meshes.filter(o => /LED_DIFFUSER/.test(o.material?.name))) {
      const box = new THREE.Box3().setFromObject(mesh), center = box.getCenter(new THREE.Vector3());
      const eye = mesh.material.name === 'LUMI_EYE_LED_DIFFUSER', count = eye ? 8 : 1;
      const a = mesh.geometry.attributes.position, n = mesh.geometry.attributes.normal, indices = [...new Set(mesh.geometry.index.array)];
      for (let step = 0; step < count; step++) {
        const aim = center.clone(); aim.z = box.max.z;
        if (eye) { const angle = step * Math.PI / 4; aim.x += Math.cos(angle) * (box.max.x - box.min.x) * .47; aim.y += Math.sin(angle) * (box.max.y - box.min.y) * .47; }
        let best = Infinity, chosen = 0;
        for (const i of indices) { scratch.fromBufferAttribute(a, i).applyMatrix4(mesh.matrixWorld); const dist = scratch.distanceToSquared(aim); if (dist < best) { best = dist; chosen = i; } }
        scratch.fromBufferAttribute(a, chosen).applyMatrix4(mesh.matrixWorld);
        const direction = new THREE.Vector3().fromBufferAttribute(n, chosen).transformDirection(mesh.matrixWorld);
        const light = new THREE.PointLight(mesh.material.emissive.clone(), 0, eye ? .023 : .024, 2);
        light.userData.power = eye ? .000022 : .000025;
        light.position.copy(scratch).addScaledVector(direction, eye ? .00055 : .0008); assembly.add(light); e.lights.push(light);
      }
    }
    host.dataset.homeReady = String(entries.filter(entry => entry.scene).length); wake();
  }
  function freeModel(model) {
    const materials = new Set(), textures = new Set();
    model.traverse(o => { if (o.isMesh) { o.geometry.dispose(); for (const m of [].concat(o.material)) materials.add(m); } });
    for (const m of materials) { for (const value of Object.values(m)) if (value?.isTexture) textures.add(value); m.dispose(); }
    for (const t of textures) { t.source?.data?.close?.(); t.dispose(); }
  }
  function dispose() {
    if (disposed) return; disposed = true; stop(); abort.abort(); resizeObserver.disconnect(); panelObserver.disconnect();
    for (const e of entries) { if (e.model) freeModel(e.model); e.environment?.dispose(); e.key?.shadow.map?.dispose(); e.button.remove(); }
    neutralEnvironment.dispose(); pmrem.dispose(); renderTarget.dispose(); quad.geometry.dispose(); quadMaterial.dispose(); glowMaterial.dispose(); renderer.dispose(); renderer.forceContextLoss(); renderer.domElement.remove();
  }
  renderReady = true; resize();
  const ready = (async () => {
    // Downloads overlap; decode/compile in order to avoid a mobile startup spike.
    for (const entry of entries) {
      await load(entry);
      if (disposed) throw new Error('LUMI home closed during preparation');
      await renderer.compileAsync(entry.scene, camera);
      onPrepared(entry.item.id);
    }
    await renderer.compileAsync(composite, quadCamera);
    await renderer.compileAsync(glowScene, quadCamera);
    resize(); draw(performance.now()); stop();
    if (renderer.getContext().isContextLost()) throw new Error('LUMI home graphics context lost during preparation');
  })();
  return { select, ready, dispose, resume() { paused = false; elapsed = 0; last = 0; wake(); } };
}
