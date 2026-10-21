(() => {
  "use strict";
  const config = window.ROOM_SITE_CONFIG || {};
  const email = typeof config.publicSupportEmail === "string" ? config.publicSupportEmail.trim() : "";
  const validEmail = /^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$/i.test(email);
  if (validEmail) {
    document.querySelectorAll("[data-support-link]").forEach(link => {
      link.href = `mailto:${email}?subject=${encodeURIComponent(document.title.startsWith("Privacy") ? "Room privacy question" : "Room support")}`;
      link.hidden = false;
    });
    document.querySelectorAll("[data-support-pending]").forEach(item => { item.hidden = true; });
  }
  let appStoreURL;
  try {
    const candidate = new URL(config.appStoreURL || "");
    if (candidate.protocol === "https:" && candidate.hostname === "apps.apple.com") appStoreURL = candidate.href;
  } catch { /* A missing URL keeps the honest coming-soon state. */ }
  if (appStoreURL) {
    document.querySelectorAll("[data-store-cta]").forEach(link => {
      link.href = appStoreURL;
      link.textContent = "View on the Mac App Store ↗";
    });
    document.querySelectorAll("[data-release-status]").forEach(item => { item.textContent = "Available on the Mac App Store."; });
  }
  if (typeof config.lastUpdated === "string" && config.lastUpdated.trim()) {
    document.querySelectorAll("[data-updated]").forEach(item => { item.textContent = config.lastUpdated.trim(); });
  }
  const controls = document.querySelector(".explorer-controls");
  if (!controls) return;
  const tabs = Array.from(controls.querySelectorAll("[data-explore]"));
  const panels = Array.from(document.querySelectorAll("[data-panel]"));
  const activate = tab => {
    tabs.forEach(item => {
      const chosen = item === tab;
      item.setAttribute("aria-selected", String(chosen));
      item.tabIndex = chosen ? 0 : -1;
    });
    panels.forEach(panel => { panel.hidden = panel.dataset.panel !== tab.dataset.explore; });
  };
  controls.hidden = false;
  tabs.forEach((tab, index) => {
    tab.addEventListener("click", () => activate(tab));
    tab.addEventListener("keydown", event => {
      let target;
      if (event.key === "ArrowRight") target = (index + 1) % tabs.length;
      if (event.key === "ArrowLeft") target = (index + tabs.length - 1) % tabs.length;
      if (event.key === "Home") target = 0;
      if (event.key === "End") target = tabs.length - 1;
      if (target === undefined) return;
      event.preventDefault();
      activate(tabs[target]);
      tabs[target].focus();
    });
  });
})();

/* Progressive motion: content is never hidden while waiting for JavaScript. */
(() => {
  "use strict";
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  const desktop = window.matchMedia("(min-width: 761px)");
  const easeOut = "cubic-bezier(0.23, 1, 0.32, 1)";
  const easeInOut = "cubic-bezier(0.77, 0, 0.175, 1)";
  let observer;
  if (!reduce.matches && "IntersectionObserver" in window && Element.prototype.animate) {
    observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return;
        observer.unobserve(entry.target);
        const node = entry.target;
        const group = node.matches(".care-sequence article,.capability-list p") ? 35 : 0;
        node.animate([
          { opacity: 0.25, transform: "translateY(18px)" },
          { opacity: 1, transform: "translateY(0)" }
        ], { duration: 600, easing: easeOut, delay: group, fill: "none" });
      });
    }, { rootMargin: "0px 0px -45px 0px", threshold: 0.08 });
    document.querySelectorAll(".section-intro,.explorer,.memory-layout h2,.memory-copy>p,.capability-list p,.care-sequence article,.faq-pair,.help-group,.contact-section,.policy-copy section").forEach(node => observer.observe(node));
  }

  const tabs = Array.from(document.querySelectorAll("[data-explore]"));
  tabs.forEach(tab => {
    tab.addEventListener("click", event => {
      if (event.detail === 0 || reduce.matches || !Element.prototype.animate) return;
      const panel = document.querySelector(`[data-panel="${tab.dataset.explore}"]`);
      if (!panel) return;
      panel.getAnimations().forEach(animation => animation.cancel());
      panel.animate([{ opacity: 0.5 }, { opacity: 1 }], { duration: 200, easing: easeOut });
      panel.querySelectorAll(".map-tile,.memory-rings>span,.memory-words>span,.review-paper,.review-word").forEach((node, index) => {
        node.getAnimations().forEach(animation => animation.cancel());
        node.animate([
          { opacity: 0.3, transform: "translateY(8px)" },
          { opacity: 1, transform: "translateY(0)" }
        ], { duration: 250, easing: easeOut, delay: Math.min(index, 3) * 40 });
      });
    });
  });

  const path = document.querySelector(".care-path");
  const stages = path ? Array.from(path.querySelectorAll("[data-care-stage]")) : [];
  const nodes = path ? Array.from(path.querySelectorAll("[data-flow-stage]")) : [];
  const marker = path?.querySelector(".flow-marker");
  const pageProgress = document.createElement("div");
  pageProgress.className = "page-progress";
  pageProgress.setAttribute("aria-hidden", "true");
  document.body.append(pageProgress);
  let queued = false;
  let lastStage = -1;
  const clamp = value => Math.max(0, Math.min(1, value));
  const update = () => {
    queued = false;
    if (reduce.matches) return;
    const maximum = document.documentElement.scrollHeight - window.innerHeight;
    pageProgress.style.transform = `scaleX(${maximum > 0 ? clamp(window.scrollY / maximum) : 1})`;
    if (!path || !marker || !desktop.matches || stages.length !== 3) return;
    path.dataset.motionReady = "";
    const first = stages[0].getBoundingClientRect();
    const last = stages[2].getBoundingClientRect();
    const center = window.innerHeight * 0.52;
    const start = first.top + first.height / 2;
    const end = last.top + last.height / 2;
    const progress = clamp((center - start) / Math.max(1, end - start));
    marker.style.transform = `translateY(${208 * progress}px)`;
    const stage = Math.round(progress * 2);
    if (stage !== lastStage) {
      nodes.forEach((node, index) => node.toggleAttribute("data-current", index === stage));
      lastStage = stage;
    }
  };
  const schedule = () => { if (!queued) { queued = true; window.requestAnimationFrame(update); } };
  window.addEventListener("scroll", schedule, { passive: true });
  window.addEventListener("resize", schedule, { passive: true });
  reduce.addEventListener("change", () => {
    observer?.disconnect();
    if (reduce.matches) {
      document.getAnimations().forEach(animation => animation.cancel());
      path?.removeAttribute("data-motion-ready");
      if (marker) marker.style.transform = "none";
    }
    schedule();
  });
  desktop.addEventListener("change", () => {
    if (!desktop.matches) path?.removeAttribute("data-motion-ready");
    schedule();
  });
  update();
})();
