#!/usr/bin/env node
/**
 * Pagina invito dell'onboarding: chi la vede, chi condivide, chi completa.
 * Funnel chiusi GA4 (utenti unici) per Android e iOS, su tutte le versioni e
 * solo sulle versioni che portano le correzioni del 01/10/2026 (Android 2.4.5:
 * rientro dalla condivisione = Home; entrambe: bottoni fissi in basso).
 *
 * Solo lettura. Token: impersonazione di ga4-reader, come ga4-daily-report.js.
 *
 *   node scripts/ga4-invite-page-funnel.js [--from 2026-09-19] [--to ieri]
 */
const { execFileSync } = require("child_process");

const PROPERTY = "523225071";
const NEW_VERSION = { Android: "2.4.5", iOS: "2.3.9" };

function arg(name, dflt) {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 && process.argv[i + 1] ? process.argv[i + 1] : dflt;
}
const yesterday = new Date(Date.now() - 864e5).toLocaleDateString("sv-SE", { timeZone: "Europe/Rome" });
const FROM = arg("from", "2026-09-19");
const TO = arg("to", yesterday);

const tok = execFileSync("gcloud", [
  "auth", "print-access-token",
  "--impersonate-service-account=ga4-reader@kidbox-42cd7.iam.gserviceaccount.com",
  "--scopes=https://www.googleapis.com/auth/analytics.readonly",
], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();

const field = (fieldName, value) => ({ funnelFieldFilter: { fieldName, stringFilter: { value } } });

async function funnel(platform, version, steps) {
  const extra = [field("platform", platform)];
  if (version) extra.push(field("appVersion", version));
  const body = {
    dateRanges: [{ startDate: FROM, endDate: TO }],
    funnel: {
      isOpenFunnel: false,
      steps: steps.map(([name, event]) => ({
        name,
        filterExpression: { andGroup: { expressions: [{ funnelEventFilter: { eventName: event } }, ...extra] } },
      })),
    },
  };
  const r = await fetch(`https://analyticsdata.googleapis.com/v1alpha/properties/${PROPERTY}:runFunnelReport`, {
    method: "POST",
    headers: { Authorization: `Bearer ${tok}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const j = await r.json();
  if (j.error) return `errore: ${j.error.message}`;
  const rows = j.funnelTable?.rows || [];
  if (!rows.length) return "nessun dato (versione non ancora in uso)";
  return rows.map((row) => row.metricValues[0].value).join(" → ");
}

(async () => {
  console.log(`# Pagina invito dell'onboarding — ${FROM} → ${TO} (utenti unici, funnel chiusi)`);
  for (const platform of ["Android", "iOS"]) {
    for (const version of [null, NEW_VERSION[platform]]) {
      const label = `${platform} ${version ? `solo ${version}` : "tutte le versioni"}`;
      const all = await funnel(platform, version, [
        ["pagina", "onboarding_invite_step_shown"],
        ["completa", "onboarding_completed"],
        ["riapre", "session_start"],
      ]);
      const share = await funnel(platform, version, [
        ["pagina", "onboarding_invite_step_shown"],
        ["condivide", "invite_shared"],
        ["completa", "onboarding_completed"],
      ]);
      console.log(`${label.padEnd(32)} pagina → completa → riapre: ${all}   |   pagina → condivide → completa: ${share}`);
    }
  }
})();
