(function () {
  const $ = (id) => document.getElementById(id);
  const post = (msg) => {
    try { window.webkit.messageHandlers.exe.postMessage(msg); } catch (e) { console.log("[bridge]", msg); }
  };

  let mood = "chill";
  let typing = null;
  let audio = null;

  function blip() {
    try {
      audio = audio || new (window.AudioContext || window.webkitAudioContext)();
      const o = audio.createOscillator(), g = audio.createGain();
      o.type = "square";
      o.frequency.value = { furious: 220, scolding: 330, sulking: 160 }[mood] || 520;
      g.gain.value = 0.025;
      o.connect(g); g.connect(audio.destination);
      o.start(); o.stop(audio.currentTime + 0.03);
    } catch (e) {}
  }

  function redraw(blink) { Sprite.draw($("sprite"), mood, blink); }

  function puff(char, color) {
    const p = document.createElement("div");
    p.className = "puff"; p.textContent = char; p.style.color = color;
    p.style.left = 30 + Math.random() * 70 + "px"; p.style.top = 10 + Math.random() * 20 + "px";
    $("fx").appendChild(p);
    setTimeout(() => p.remove(), 1000);
  }

  function hpColor(a) { return a > 60 ? "#5dff8a" : a > 35 ? "#ffd36b" : a > 15 ? "#ff9b4d" : "#ff3355"; }

  window.ex = {
    setState(s) {
      if (s.mood !== mood) { mood = s.mood; document.body.className = mood; redraw(false); }
      document.body.classList.toggle("handsoff", !!s.handsOff);
      $("mood").textContent = s.label;
      $("hpfill").style.width = Math.max(0, Math.min(100, s.affection)) + "%";
      $("hpfill").style.background = hpColor(s.affection);
      $("hpnum").textContent = s.affection;
      $("appname").textContent = s.app;
      if (s.name) { $("name").textContent = s.name.toUpperCase(); $("tag").textContent = s.name.toUpperCase(); }
    },
    say({ text }) {
      clearInterval(typing);
      $("caret").classList.remove("on");
      const el = $("text"); el.textContent = "";
      let i = 0;
      const speed = mood === "furious" ? 18 : mood === "sulking" ? 70 : 32;
      typing = setInterval(() => {
        el.textContent += text[i];
        if (text[i] !== " " && i % 2 === 0) blip();
        i++;
        if (i >= text.length) { clearInterval(typing); $("caret").classList.add("on"); }
      }, speed);
      if (mood === "furious") { puff("💢", "#ff3355"); puff("!!", "#fff"); }
      if (mood === "forgiving") puff("♥", "#ff7b9c");
      if (mood === "sulking") puff("…", "#aaa");
    },
    fx({ name }) {
      document.body.classList.add(name);
      setTimeout(() => document.body.classList.remove(name), name === "spotlight" ? 3200 : 700);
      if (name === "shake") puff("!?", "#ffd36b");
    },
  };

  $("ack").onclick = () => { post({ type: "ack" }); $("caret").classList.remove("on"); };
  $("sorry").onclick = () => post({ type: "sorry" });
  $("box").onclick = (e) => { if (e.target.tagName !== "BUTTON") post({ type: "ack" }); };

  // idle blink
  setInterval(() => { redraw(true); setTimeout(() => redraw(false), 140); }, 3800);
  setInterval(() => { if (mood === "furious") puff("💢", "#ff3355"); }, 1500);

  document.body.className = mood;
  redraw(false);
  post({ type: "ready" });
})();
