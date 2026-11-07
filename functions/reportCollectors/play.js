/* eslint-disable -- stile degli script (prettier), condiviso con scripts/ */
/**
 * Raccolta di crash/ANR (Play Developer Reporting API) e recensioni (Android
 * Publisher API): UNICA copia, usata da `scripts/play-daily-report.js` e dalla
 * funzione `reportSnapshotStoreDaily`. Le installazioni NON sono qui: vengono
 * da export manuale e dal bucket, che una funzione non legge.
 * Chi chiama passa i due token: `{ reporting, publisher }`.
 */

const PACKAGE = "it.vittorioscocca.kidbox";

function romeDate(d = new Date()) {
  return d.toLocaleDateString("sv-SE", { timeZone: "Europe/Rome" });
}
function shiftDay(iso, n) {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

async function errorCounts(tok, startIso, endIso) {
  const day = (iso) => {
    const [y, m, d] = iso.split("-").map(Number);
    return { year: y, month: m, day: d, timeZone: { id: "America/Los_Angeles" } };
  };
  const res = await fetch(
    `https://playdeveloperreporting.googleapis.com/v1beta1/apps/${PACKAGE}/errorCountMetricSet:query`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${tok}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        timelineSpec: { aggregationPeriod: "DAILY", startTime: day(startIso), endTime: day(endIso) },
        metrics: ["errorReportCount", "distinctUsers"],
        dimensions: ["reportType"],
        pageSize: 1000,
      }),
    }
  );
  const json = await res.json();
  if (!res.ok) throw new Error(`Reporting API: ${json.error?.message || res.status}`);
  return (json.rows || []).map((r) => {
    const t = r.startTime;
    const metrics = Object.fromEntries(r.metrics.map((m) => [m.metric, Number(m.decimalValue?.value || 0)]));
    return {
      date: `${t.year}-${String(t.month).padStart(2, "0")}-${String(t.day).padStart(2, "0")}`,
      type: r.dimensions?.[0]?.stringValue || "?",
      reports: metrics.errorReportCount || 0,
      users: metrics.distinctUsers || 0,
    };
  });
}

// ------------------------------------------------------------ Recensioni

async function reviews(tok) {
  const res = await fetch(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE}/reviews?maxResults=20`,
    { headers: { Authorization: `Bearer ${tok}` } }
  );
  const json = await res.json();
  if (!res.ok) throw new Error(`Publisher API: ${json.error?.message || res.status}`);
  return (json.reviews || []).map((r) => {
    const c = r.comments?.[0]?.userComment || {};
    return {
      date: new Date(Number(c.lastModified?.seconds || 0) * 1000).toISOString().slice(0, 10),
      stars: c.starRating,
      version: c.appVersionName,
      lang: c.reviewerLanguage,
      text: (c.text || "").replace(/\s+/g, " ").trim().slice(0, 160),
      replied: (r.comments || []).some((x) => x.developerComment),
    };
  });
}

async function collect({ reporting, publisher }) {
  const yesterday = shiftDay(romeDate(), -1);
  const errors = await errorCounts(reporting, shiftDay(yesterday, -13), yesterday);
  const revs = await reviews(publisher);
  return { package: PACKAGE, yesterday, errors, reviews: revs };
}

module.exports = { collect, errorCounts, reviews, PACKAGE };
