// Tidewatch download page: reveal on scroll, looping demo videos, the beats synced to the hero
// video, the dark/light switch and the checksum copy button.
(() => {
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const header = document.querySelector("[data-header]");
  if (header) {
    const onScroll = () => header.classList.toggle("is-scrolled", window.scrollY > 24);
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
  }

  // Reveal: each block fades up once when it enters the viewport.
  const revealed = document.querySelectorAll("[data-reveal]");
  if ("IntersectionObserver" in window && !reduceMotion) {
    const io = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        entry.target.classList.add("is-in");
        io.unobserve(entry.target);
      }
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });
    revealed.forEach((el) => io.observe(el));
  } else {
    revealed.forEach((el) => el.classList.add("is-in"));
  }

  // Videos play only while on screen. With reduced motion they wait for a click.
  const videos = [...document.querySelectorAll("video[data-loop]")];
  const play = (video) => { const p = video.play(); if (p) p.catch(() => {}); };
  if (reduceMotion) {
    videos.forEach((video) => { video.controls = true; });
  } else if ("IntersectionObserver" in window) {
    const vo = new IntersectionObserver((entries) => {
      for (const entry of entries) entry.isIntersecting ? play(entry.target) : entry.target.pause();
    }, { threshold: 0.25 });
    videos.forEach((video) => vo.observe(video));
  } else {
    videos.forEach(play);
  }

  // Beats: light the step of the cycle the hero video is showing (times in seconds into the video).
  const beatsVideo = document.querySelector("video[data-beats]");
  const beats = [...document.querySelectorAll(".beats li[data-at]")];
  if (beatsVideo && beats.length) {
    const times = beats.map((li) => parseFloat(li.dataset.at));
    let current = -1;
    const tick = () => {
      const t = beatsVideo.currentTime;
      const duration = beatsVideo.duration || 12;
      let index = times.findLastIndex((at) => at <= t);
      if (index < 0) index = times.length - 1;
      if (index !== current) {
        current = index;
        const next = times[(index + 1) % times.length];
        const span = ((next - times[index]) + duration) % duration || duration;
        beats.forEach((li, i) => li.classList.toggle("is-on", i === index));
        beats[index].style.setProperty("--beat", `${span}s`);
      }
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  // Dark / light: swap the recording, keep the position in the cycle.
  const switchVideo = document.querySelector("video[data-switch]");
  const switches = [...document.querySelectorAll("[data-theme-video]")];
  if (switchVideo && switches.length) {
    switches.forEach((button) => button.addEventListener("click", () => {
      const theme = button.dataset.themeVideo;
      if (button.getAttribute("aria-pressed") === "true") return;
      switches.forEach((b) => b.setAttribute("aria-pressed", String(b === button)));
      const at = switchVideo.currentTime;
      const wasPlaying = !switchVideo.paused;
      switchVideo.poster = `assets/video/demo-${theme}.webp`;
      switchVideo.querySelector("source").src = `assets/video/demo-${theme}.mp4`;
      switchVideo.load();
      switchVideo.addEventListener("loadedmetadata", () => {
        switchVideo.currentTime = at;
        if (wasPlaying || !reduceMotion) play(switchVideo);
      }, { once: true });
    }));
  }

  const copy = document.querySelector("[data-copy]");
  const sha = document.querySelector("[data-sha]");
  if (copy && sha && navigator.clipboard) {
    copy.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(sha.textContent.trim());
        copy.textContent = "Copied";
      } catch {
        copy.textContent = "Select it";
      }
      setTimeout(() => { copy.textContent = "Copy"; }, 1600);
    });
  } else if (copy) {
    copy.hidden = true;
  }
})();
