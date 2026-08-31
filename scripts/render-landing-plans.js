#!/usr/bin/env node
/**
 * Rigenera le card dei piani nella landing a partire dalla fonte di verità
 * unica: `functions/plans.json`.
 *
 *   node scripts/render-landing-plans.js          # riscrive index.html / index-en.html
 *   node scripts/render-landing-plans.js --check  # esce 1 se sono disallineate (CI)
 *
 * Sostituisce solo ciò che sta tra i marcatori PLANS:START / PLANS:END, così il
 * resto della pagina resta scritto a mano com'è sempre stato.
 * Vedi `internal/plans-source-of-truth.md`.
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const PLANS = require(path.join(ROOT, "functions", "plans.json"));

const START = "<!-- PLANS:START — generato da scripts/render-landing-plans.js, non modificare a mano -->";
const END = "<!-- PLANS:END -->";

/** Pagine da rigenerare, con la lingua dei testi da prendere dal catalogo. */
const TARGETS = [
  {file: path.join(ROOT, "KidboxLanding", "public", "index.html"), lang: "it"},
  {file: path.join(ROOT, "KidboxLanding", "public", "index-en.html"), lang: "en"},
];

// Renderer condiviso con la landing: la pagina lo ricarica a runtime per
// riallinearsi a `config/plans`, quindi HTML generato e HTML vivo devono uscire
// dalla stessa funzione, non da due copie che divergono.
const {renderPlanCards} = require(path.join(ROOT, "KidboxLanding", "public", "assets", "plans.js"));

function render(lang) {
  return [
    START,
    '  <div class="plans rv">',
    renderPlanCards(PLANS.plans, lang),
    "  </div>",
    END,
  ].join("\n");
}

const check = process.argv.includes("--check");
let failed = false;

for (const {file, lang} of TARGETS) {
  const html = fs.readFileSync(file, "utf8");
  const start = html.indexOf(START);
  const end = html.indexOf(END);
  if (start === -1 || end === -1) {
    console.error(`✗ ${path.basename(file)}: marcatori PLANS:START/PLANS:END non trovati`);
    failed = true;
    continue;
  }

  const next = html.slice(0, start) + render(lang) + html.slice(end + END.length);
  if (next === html) {
    console.log(`= ${path.basename(file)}: già allineata`);
    continue;
  }
  if (check) {
    console.error(`✗ ${path.basename(file)}: disallineata da functions/plans.json`);
    failed = true;
    continue;
  }
  fs.writeFileSync(file, next);
  console.log(`✓ ${path.basename(file)}: card piani rigenerate`);
}

process.exit(failed ? 1 : 0);
