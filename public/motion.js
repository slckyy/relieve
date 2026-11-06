(() => {
  const preference = matchMedia('(prefers-reduced-motion: reduce)');
  const ease = 'cubic-bezier(.22, 1, .36, 1)';
  const running = new Set();
  const byNode = new WeakMap();
  const duration = value => preference.matches ? Math.min(value, 80) : value;
  function animate(node, frames, ms = 560, easing = ease) {
    if (!node?.isConnected) return Promise.resolve();
    const animation = node.animate(frames, { duration: duration(ms), easing });
    running.add(animation);
    if (!byNode.has(node)) byNode.set(node, new Set());
    byNode.get(node).add(animation);
    return animation.finished.catch(() => {}).finally(() => {
      running.delete(animation); byNode.get(node).delete(animation);
    });
  }
  function stop(node) {
    for (const animation of byNode.get(node) || []) animation.cancel();
  }
  preference.addEventListener('change', () => {
    if (preference.matches) for (const animation of running) animation.finish();
  });
  const visible = node => {
    if (!node?.isConnected || node.closest('.panel[hidden], [inert]')) return false;
    const rect = node.getBoundingClientRect();
    return rect.width > 0 && rect.bottom > 0 && rect.top < innerHeight;
  };
  let lastTrigger = null;
  // Capture the actual tapped control: Safari does not always focus buttons.
  // A complete recoil plays even after a very short tap or keyboard activation.
  document.addEventListener('click', event => {
    const control = event.target.closest?.('button, a.client-name, .client-details a');
    if (!control || control.disabled || control.closest('[inert], .is-closing')) return;
    lastTrigger = { node: control, rect: control.getBoundingClientRect(), at: performance.now() };
    stop(control);
    animate(control, preference.matches ? [{ opacity: .65 }, { opacity: 1 }] : [
      { scale: '.90 .94', offset: 0, easing: ease },
      { scale: '1.045 1.025', offset: .55, easing: ease },
      { scale: '.992 1.005', offset: .8, easing: ease },
      { scale: '1', offset: 1 }
    ], 560, 'linear');
  }, true);

  function page(node) {
    stop(node);
    return animate(node, preference.matches ? [{ opacity: .7 }, { opacity: 1 }] : [
      { transform: 'translateY(34px) scale(.94)', offset: 0, easing: ease },
      { transform: 'translateY(-3px) scale(1.008)', offset: .72, easing: ease },
      { transform: 'none', offset: 1 }
    ], 760, 'linear');
  }

  // Keep the native modal focus trap and top layer until its exit has finished.
  function dialog(dialog, body, isBusy) {
    let closing = null, previous = null, opener, origin;
    function sourceTransform() {
      const surface = dialog.getBoundingClientRect();
      const source = origin || { left: surface.left + surface.width / 2, top: surface.top + surface.height / 2 + 70, width: 0, height: 0 };
      const x = source.left + source.width / 2 - surface.left - surface.width / 2;
      const y = source.top + source.height / 2 - surface.top - surface.height / 2;
      const sx = Math.max(.16, Math.min(.65, source.width / surface.width));
      const sy = Math.max(.10, Math.min(.35, source.height / surface.height));
      return `translate(${x}px, ${y}px) scale(${sx}, ${sy})`;
    }
    const finish = () => {
      if (previous) {
        const { copy, height, transform } = previous;
        previous = null;
        stop(dialog);
        stop(body);
        const nextHeight = dialog.offsetHeight;
        if (!preference.matches && (Math.abs(height - nextHeight) > 1 || transform !== 'none')) {
          animate(dialog, [
            { height: `${height}px`, transform, offset: 0, easing: ease },
            { height: `${nextHeight}px`, transform: 'scale(1.035, .985)', offset: .65, easing: ease },
            { height: `${nextHeight}px`, transform: 'scale(.992, 1.012)', offset: .84, easing: ease },
            { height: `${nextHeight}px`, transform: 'none', offset: 1 }
          ], 680, 'linear');
        }
        animate(copy, [{ opacity: 1 }, { opacity: 0 }], 280).then(() => copy.remove());
        animate(body, [{ opacity: 0, transform: preference.matches ? 'none' : 'translateY(18px)' }, { opacity: 1, transform: 'none' }], 540);
      }
    };
    function prepare() {
      body.scrollTop = 0;
      if (!dialog.open || closing) return;
      dialog.querySelectorAll('.motion-dialog-copy').forEach(node => node.remove());
      const copy = body.cloneNode(true);
      copy.classList.add('motion-dialog-copy');
      copy.setAttribute('aria-hidden', 'true');
      copy.inert = true;
      copy.querySelectorAll('[id]').forEach(node => node.removeAttribute('id'));
      Object.assign(copy.style, { left: `${body.offsetLeft}px`, top: `${body.offsetTop}px`, width: `${body.offsetWidth}px`, height: `${body.offsetHeight}px` });
      previous = { copy, height: dialog.offsetHeight, transform: getComputedStyle(dialog).transform };
      stop(dialog);
      dialog.append(copy);
    }
    function open() {
      if (closing) return;
      if (dialog.open) { finish(); return; }
      const trigger = lastTrigger && performance.now() - lastTrigger.at < 800 ? lastTrigger : null;
      opener = trigger?.node || document.activeElement;
      origin = trigger?.rect || (visible(opener) ? opener.getBoundingClientRect() : null);
      dialog.classList.remove('is-closing');
      dialog.showModal();
      animate(dialog, preference.matches ? [{ opacity: 0, transform: 'none' }, { opacity: 1, transform: 'none' }] : [
        { opacity: .15, transform: sourceTransform(), borderRadius: '44px', offset: 0, easing: ease },
        { opacity: 1, transform: 'scale(1.06, .96)', borderRadius: '24px', offset: .60, easing: ease },
        { opacity: 1, transform: 'scale(.985, 1.025)', borderRadius: '20px', offset: .80, easing: ease },
        { opacity: 1, transform: 'none', borderRadius: '20px', offset: 1 }
      ], 780, 'linear');
    }
    function close(force = false) {
      if (closing) return closing;
      if (!dialog.open || (!force && isBusy())) return Promise.resolve();
      const current = getComputedStyle(dialog);
      const from = { opacity: current.opacity, transform: current.transform };
      stop(dialog);
      if (opener?.isConnected && visible(opener)) origin = opener.getBoundingClientRect();
      const destination = sourceTransform();
      dialog.classList.add('is-closing');
      // Prevent repeated actions during the exit, without dropping modal focus.
      body.inert = true;
      closing = animate(dialog, preference.matches ? [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'none' }] : [
        { ...from, offset: 0, easing: ease },
        { opacity: 1, transform: 'scale(1.035, .97)', offset: .23, easing: 'cubic-bezier(.5, 0, .75, .35)' },
        { opacity: 0, transform: destination, borderRadius: '44px', offset: 1 }
      ], 560, 'linear').then(() => {
        dialog.close();
        body.inert = false;
        dialog.classList.remove('is-closing');
        dialog.querySelectorAll('.motion-dialog-copy').forEach(node => node.remove());
        previous = null;
        closing = null;
        if (opener?.isConnected && visible(opener)) opener.focus({ preventScroll: true });
      });
      return closing;
    }
    dialog.addEventListener('cancel', event => { event.preventDefault(); close(); });
    dialog.addEventListener('click', event => {
      if (closing) { event.preventDefault(); event.stopImmediatePropagation(); }
    }, true);
    return { prepare, open, close, finish };
  }

  // Animate stable record identities, not a wholesale replacement of the list.
  function updateLists(lists, change) {
    const before = new Map();
    const key = node => node.dataset.clientId ? `client:${node.dataset.clientId}` : `event:${node.dataset.eventId}`;
    for (const list of lists) for (const node of list.children) {
      if (!visible(node)) continue;
      before.set(key(node), { node, rect: node.getBoundingClientRect(), text: node.textContent,
        color: getComputedStyle(node.querySelector('.client-name')).color,
        scroll: list.closest('.page-scroll') });
    }
    change();
    const pending = [];
    for (const list of lists) for (const node of list.children) {
      const old = before.get(key(node));
      if (!visible(node)) continue;
      if (old) before.delete(key(node));
      const rect = node.getBoundingClientRect();
      if (!old) {
        pending.push(animate(node, preference.matches ? [{ opacity: 0 }, { opacity: 1 }] : [
          { opacity: 0, transform: 'translateY(28px) scale(.92, .88)', offset: 0, easing: ease },
          { opacity: 1, transform: 'translateY(-3px) scale(1.02, 1.035)', offset: .65, easing: ease },
          { opacity: 1, transform: 'none', offset: 1 }
        ], 680, 'linear'));
      } else {
        const dx = old.rect.left - rect.left, dy = old.rect.top - rect.top;
        if (!preference.matches && (Math.abs(dx) > .5 || Math.abs(dy) > .5)) {
          pending.push(animate(node, [
            { transform: `translate(${dx}px, ${dy}px)`, offset: 0, easing: ease },
            { transform: `translate(${-dx * .035}px, ${-dy * .035}px)`, offset: .72, easing: ease },
            { transform: 'none', offset: 1 }
          ], 680, 'linear'));
        }
        if (old.text !== node.textContent) pending.push(animate(node, [{ opacity: .55 }, { opacity: 1 }], 440));
        for (const text of node.querySelectorAll('.client-name, .client-details-button, .client-send-button')) {
          const color = getComputedStyle(text).color;
          if (old.color !== color) pending.push(animate(text, [{ color: old.color }, { color }], 540));
        }
      }
    }
    for (const old of before.values()) {
      if (old.scroll.closest('.panel').hidden) continue;
      const ghost = document.createElement('div');
      ghost.className = 'motion-departure';
      ghost.setAttribute('aria-hidden', 'true');
      ghost.inert = true;
      const copy = old.node.cloneNode(true);
      copy.querySelectorAll('[id]').forEach(node => node.removeAttribute('id'));
      ghost.append(copy);
      const parent = old.scroll.getBoundingClientRect();
      Object.assign(ghost.style, { left: `${old.rect.left - parent.left}px`, top: `${old.rect.top - parent.top + old.scroll.scrollTop}px`, width: `${old.rect.width}px` });
      old.scroll.append(ghost);
      pending.push(animate(ghost, [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: preference.matches ? 'none' : 'translateY(-12px) scale(.88, .72)' }], 480).then(() => ghost.remove()));
    }
    return Promise.all(pending);
  }
  const messageStates = new WeakMap();
  function message(node, text, failed = false) {
    const generation = (messageStates.get(node) || 0) + 1;
    messageStates.set(node, generation);
    node.getAnimations().forEach(animation => animation.cancel());
    node.textContent = text;
    node.setAttribute('role', failed ? 'alert' : 'status');
    node.hidden = false;
    animate(node, preference.matches ? [{ opacity: 0 }, { opacity: 1 }] : [
      { opacity: 0, transform: 'translateY(24px) scale(.94)', offset: 0, easing: ease },
      { opacity: 1, transform: 'translateY(-3px) scale(1.015)', offset: .70, easing: ease },
      { opacity: 1, transform: 'none', offset: 1 }
    ], 620, 'linear');
  }
  function hideMessage(node) {
    if (node.hidden) return;
    const generation = (messageStates.get(node) || 0) + 1;
    messageStates.set(node, generation);
    node.getAnimations().forEach(animation => animation.cancel());
    animate(node, [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: preference.matches ? 'none' : 'translateY(18px) scale(.95)' }], 420).then(() => {
      if (messageStates.get(node) === generation) node.hidden = true;
    });
  }
  function text(node, value) {
    if (node.textContent === value) return;
    node.textContent = value;
    if (visible(node)) animate(node, [{ opacity: .35, transform: preference.matches ? 'none' : 'translateY(8px)' }, { opacity: 1, transform: 'none' }], 480);
  }
  window.SanctionMotion = Object.freeze({ ease, duration, animate, dialog, updateLists, message, hideMessage, text, page });
})();
