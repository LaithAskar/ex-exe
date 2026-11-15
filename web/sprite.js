// 20x22 pixel-art bust of Vex. Base map + per-expression face patches.
(function () {
  const PAL = {
    K: "#1a1022", H: "#5b2a86", h: "#9a5bd6", S: "#f2c6a0", s: "#d99c7a",
    W: "#ffffff", E: "#2b1b3a", B: "#ff7b9c", C: "#e8475f", c: "#a82a43", M: "#7a2b3a", R: "#ff3355", G: "#7dffb0",
  };
  const BASE = [
    "......KKKKKKKK......",
    "....KKHHHHHHHHKK....",
    "...KHHHhhHHHHHHHK...",
    "..KHHhHHHHHHHHHHHK..",
    "..KHHHHHHHHHHHHHHK..",
    ".KHHHHHHHHHHHHHHHHK.",
    ".KHHHSSHHHHHSSSHHHK.",
    ".KHHSSSSSSSSSSSSHHK.",
    ".KHSSSSSSSSSSSSSSHK.",
    ".KHSSSSSSSSSSSSSSHK.",
    ".KHSSSSSSSSSSSSSSHK.",
    ".KHSSSSSSSSSSSSSSHK.",
    ".KHHSSSSSSSSSSSSHHK.",
    ".KHHSSSSSSSSSSSSHHK.",
    ".KHHHsSSSSSSSSsHHHK.",
    ".KHHHKsSSSSSSsKHHHK.",
    "..KHHHKKSSSSKKHHHK..",
    "..KHHKCCKSSKCCKHHK..",
    ".KHHKCCCCCCCCCCKHHK.",
    "KHHKCCCCCcCCCCCCKHHK",
    "KHKCCCCCCcCCCCCCCKHK",
    "KKCCCCCCCcCCCCCCCCKK",
  ];

  // [x, y, rows] patches; '.' = leave base pixel.
  const EYES = {
    open:    [[5, 9, ["KKK", "WEE"]], [12, 9, ["KKK", "EEW"]]],
    side:    [[5, 9, ["KKK", "EEW"]], [12, 9, ["KKK", "EEW"]]],
    angry:   [[4, 8, ["KK..", ".KKK", ".WEE"]], [12, 8, ["..KK", "KKK.", "EEW."]]],
    furious: [[4, 8, ["KK..", ".KKK", ".RER"]], [12, 8, ["..KK", "KKK.", "RER."]]],
    half:    [[5, 9, ["...", "KKK"]], [12, 9, ["...", "KKK"]]],
    closed:  [[5, 10, ["KKK"]], [12, 10, ["KKK"]]],
    soft:    [[5, 9, ["...", "KEK"]], [12, 9, ["...", "KEK"]]],
  };
  const MOUTH = {
    flat:  [[8, 13, ["MMMM"]]],
    smug:  [[8, 12, ["...M"]], [8, 13, ["MMM."]]],
    frown: [[8, 12, [".MM."]], [8, 13, ["M..M"]]],
    smile: [[8, 12, ["M..M"]], [8, 13, [".MM."]]],
    yell:  [[8, 12, ["MMMM"]], [8, 13, ["MKKM"]], [8, 14, ["MMMM"]]],
    tiny:  [[9, 13, ["MM"]]],
  };
  const BLUSH = [[4, 11, ["BB"]], [14, 11, ["BB"]]];
  const VEIN = [[14, 3, ["R.R", ".R.", "R.R"]]];

  const FACES = {
    chill:             { eyes: "open", mouth: "smug" },
    passiveAggressive: { eyes: "half", mouth: "flat" },
    scolding:          { eyes: "angry", mouth: "frown" },
    furious:           { eyes: "furious", mouth: "yell", extra: [VEIN] },
    sulking:           { eyes: "side", mouth: "tiny" },
    forgiving:         { eyes: "soft", mouth: "smile", extra: [BLUSH] },
  };

  function paint(ctx, patches) {
    for (const [x0, y0, rows] of patches) {
      rows.forEach((row, dy) => [...row].forEach((ch, dx) => {
        if (ch === ".") return;
        ctx.fillStyle = PAL[ch]; ctx.fillRect(x0 + dx, y0 + dy, 1, 1);
      }));
    }
  }

  window.Sprite = {
    draw(canvas, mood, blink) {
      const ctx = canvas.getContext("2d");
      ctx.clearRect(0, 0, 20, 22);
      BASE.forEach((row, y) => [...row.padEnd(20, ".")].forEach((ch, x) => {
        if (ch === ".") return;
        ctx.fillStyle = PAL[ch]; ctx.fillRect(x, y, 1, 1);
      }));
      const f = FACES[mood] || FACES.chill;
      paint(ctx, EYES[blink && f.eyes !== "closed" ? "closed" : f.eyes]);
      paint(ctx, MOUTH[f.mouth]);
      (f.extra || []).forEach(p => paint(ctx, p));
    },
  };
})();
