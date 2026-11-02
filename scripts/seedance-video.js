#!/usr/bin/env node
/**
 * Genera un video con Seedance 2.5 (BytePlus ModelArk) e lo scarica.
 *
 *   node scripts/seedance-video.js --prompt prompt.txt --out video.mp4 \
 *        [--ratio 9:16] [--res 480p|720p|1080p] [--seconds 30] [--no-audio] \
 *        [--ref immagine.jpg]...   # riferimenti, richiamati nel prompt come @Image 1, 2…
 *   node scripts/seedance-video.js --task <id> --out video.mp4   # riprende un task già lanciato
 *
 * La chiave sta nel Portachiavi (account «kidbox», voce «byteplus-ark-key»):
 *   security add-generic-password -a kidbox -s byteplus-ark-key -w '<chiave>' -U
 *
 * Ogni generazione si paga (token del pacchetto Seedance, poi a consumo):
 * le prove si fanno a 480p, la versione buona a 1080p.
 */
const fs = require("fs");
const path = require("path");
const {execFileSync} = require("child_process");

const BASE = "https://ark.ap-southeast.bytepluses.com/api/v3/contents/generations/tasks";
const MODEL = "dreamina-seedance-2-5-260628";

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : def;
}
function args(name) {
  const out = [];
  process.argv.forEach((a, i) => { if (a === `--${name}`) out.push(process.argv[i + 1]); });
  return out;
}

function apiKey() {
  try {
    return execFileSync("security", ["find-generic-password", "-a", "kidbox", "-s", "byteplus-ark-key", "-w"], {
      stdio: ["ignore", "pipe", "ignore"],
    }).toString().trim();
  } catch {
    console.error("Chiave BytePlus non trovata nel Portachiavi (voce «byteplus-ark-key», account «kidbox»).\n" +
      "  security add-generic-password -a kidbox -s byteplus-ark-key -w '<chiave>' -U");
    process.exit(1);
  }
}

async function call(key, method, url, body) {
  // Un buco di rete durante l'attesa non deve far perdere il task: il video si
  // genera comunque sul server, quindi le letture ritentano.
  let res;
  for (let attempt = 1; ; attempt++) {
    try {
      res = await fetch(url, {
        method,
        headers: {"Authorization": `Bearer ${key}`, "Content-Type": "application/json"},
        body: body ? JSON.stringify(body) : undefined,
      });
      break;
    } catch (e) {
      if (method !== "GET" || attempt >= 10) throw e;
      process.stdout.write(`(rete: ${e.cause?.code || e.message}, riprovo) … `);
      await new Promise((r) => setTimeout(r, 15000));
    }
  }
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = {raw: text}; }
  if (!res.ok) {
    console.error(`HTTP ${res.status}:`, JSON.stringify(json, null, 2));
    process.exit(1);
  }
  return json;
}

function imageItem(file) {
  const ext = path.extname(file).slice(1).toLowerCase().replace("jpg", "jpeg");
  const data = fs.readFileSync(file).toString("base64");
  return {type: "image_url", image_url: {url: `data:image/${ext};base64,${data}`}, role: "reference_image"};
}

(async () => {
  const key = apiKey();
  const out = arg("out", "seedance.mp4");
  let id = arg("task");

  if (!id) {
    const promptFile = arg("prompt");
    if (!promptFile) { console.error("Manca --prompt <file>"); process.exit(1); }
    const body = {
      model: MODEL,
      content: [{type: "text", text: fs.readFileSync(promptFile, "utf8").trim()}, ...args("ref").map(imageItem)],
      ratio: arg("ratio", "9:16"),
      resolution: arg("res", "480p"),
      duration: Number(arg("seconds", "30")),
      generate_audio: !process.argv.includes("--no-audio"),
    };
    const created = await call(key, "POST", BASE, body);
    id = created.id;
    console.log(`task ${id} creato (${body.resolution}, ${body.ratio}, ${body.duration} s)`);
  }

  const started = Date.now();
  for (;;) {
    const t = await call(key, "GET", `${BASE}/${id}`);
    const status = t.status;
    if (status === "succeeded") {
      const url = t.content?.video_url;
      if (!url) { console.log(JSON.stringify(t, null, 2)); process.exit(1); }
      const res = await fetch(url);
      fs.writeFileSync(out, Buffer.from(await res.arrayBuffer()));
      console.log(`scaricato ${out} · token ${t.usage?.total_tokens ?? "?"} · ${Math.round((Date.now() - started) / 1000)} s`);
      return;
    }
    if (status === "failed" || status === "cancelled" || status === "expired") {
      console.error(JSON.stringify(t, null, 2));
      process.exit(1);
    }
    process.stdout.write(`${status} … `);
    await new Promise((r) => setTimeout(r, 15000));
  }
})();
