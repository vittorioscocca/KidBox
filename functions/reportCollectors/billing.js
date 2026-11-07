/* eslint-disable -- stile degli script (prettier), condiviso con scripts/ */
/**
 * Raccolta dei costi Google Cloud per il report: UNICA copia, usata da
 * `scripts/gcloud-billing-daily-report.js` (con `bq`) e dalla funzione
 * `reportSnapshotStoreDaily` (con l'API REST di BigQuery). Chi chiama passa
 * `bq(sql) -> righe`; se la tabella non esiste ancora deve lanciare un errore
 * con `notYet = true`.
 */

const PROJECT = "kidbox-42cd7";
const TABLE = `\`${PROJECT}.billing_export.gcp_billing_export_v1_015E5B_092B59_BED0B8\``;
const TZ = "Europe/Rome";

function romeDate(d = new Date()) {
  return d.toLocaleDateString("sv-SE", { timeZone: TZ });
}
function shiftDay(iso, n) {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

async function collect(bq) {
  const yesterday = shiftDay(romeDate(), -1);
  const start = shiftDay(yesterday, -13);
  const monthStart = `${yesterday.slice(0, 7)}-01`;
  const from = start < monthStart ? start : monthStart;
  const out = { project: PROJECT, yesterday, notes: [] };

  let rows;
  try {
    rows = await bq(`
      SELECT
        FORMAT_DATE('%F', DATE(usage_start_time, '${TZ}')) AS day,
        service.description AS service,
        sku.description AS sku,
        currency,
        SUM(cost) AS cost,
        SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)) AS credits,
        MAX(export_time) AS last_export
      FROM ${TABLE}
      WHERE DATE(usage_start_time, '${TZ}') BETWEEN '${from}' AND '${yesterday}'
      GROUP BY day, service, sku, currency
      ORDER BY day, service, sku
    `);
  } catch (e) {
    if (e.notYet) {
      out.notes.push("L'export della fatturazione non ha ancora scritto la tabella su BigQuery (attivato il 15/09/2026: le prime righe arrivano entro qualche ora, poi ogni giorno).");
      rows = [];
    } else {
      throw e;
    }
  }

  const num = (x) => Number(x || 0);
  out.currency = rows[0]?.currency || "EUR";
  out.lastExport = rows.reduce((a, r) => (r.last_export > a ? r.last_export : a), "") || null;
  // giorno → servizio → {cost, credits}
  const byDay = {};
  const bySku = {};
  for (const r of rows) {
    const d = (byDay[r.day] = byDay[r.day] || {});
    const s = (d[r.service] = d[r.service] || { cost: 0, credits: 0 });
    s.cost += num(r.cost);
    s.credits += num(r.credits);
    if (r.day >= shiftDay(yesterday, -6)) {
      const k = `${r.service} — ${r.sku}`;
      bySku[k] = (bySku[k] || 0) + num(r.cost) + num(r.credits);
    }
  }
  out.byDay = byDay;
  out.topSku7d = Object.entries(bySku).filter(([, v]) => Math.abs(v) >= 0.001).sort((a, b) => b[1] - a[1]).slice(0, 10);

  const dayNet = (d) => Object.values(byDay[d] || {}).reduce((a, s) => a + s.cost + s.credits, 0);
  const dayGross = (d) => Object.values(byDay[d] || {}).reduce((a, s) => a + s.cost, 0);
  const days = Object.keys(byDay).sort();
  out.totals = {
    yesterday: { gross: dayGross(yesterday), net: dayNet(yesterday), present: !!byDay[yesterday] },
    last7: [...Array(7)].reduce((a, _, i) => a + dayNet(shiftDay(yesterday, -i)), 0),
    monthNet: days.filter((d) => d >= monthStart).reduce((a, d) => a + dayNet(d), 0),
    monthGross: days.filter((d) => d >= monthStart).reduce((a, d) => a + dayGross(d), 0),
    daysWithData: days.length,
    firstDay: days[0] || null,
  };
  if (rows.length && !byDay[yesterday]) out.notes.push(`Nessuna riga per ${yesterday}: l'export del giorno arriva nel corso della giornata successiva, spesso dopo le 08:30.`);
  return out;
}

module.exports = { collect, PROJECT, TZ, romeDate, shiftDay };
