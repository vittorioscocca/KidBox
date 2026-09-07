/**
 * Storico salute — porting di `HealthTimelineView`.
 *
 * Gli eventi arrivano già uniti e ordinati da `buildTimeline`; qui restano il
 * filtro per tipo, quello per anno e la ricerca testuale, con il
 * raggruppamento anno → mese del telefono.
 */
import { useMemo, useState } from "react";
import {
  ADMINISTRATION_SITES,
  TIMELINE_KINDS,
  buildTimeline,
  examStatusInfo,
  timelineKindInfo,
  vaccineDate,
  vaccineStatusInfo,
  vaccineTypeInfo,
  visitStatusInfo,
} from "../../services/health";
import { frequencyLabel } from "../../services/healthContext";
import { DetailRow, ModuleHeader, fmtDate, label, localeTag } from "./shared";

export default function HealthTimeline({
  visits,
  exams,
  treatments,
  vaccines,
  h,
  locale,
  onBack,
}) {
  const s = h.timeline;
  const [kinds, setKinds] = useState([]);
  const [year, setYear] = useState(null);
  const [search, setSearch] = useState("");
  const [openEvent, setOpenEvent] = useState(null);

  /** Il record dietro l'evento cliccato: la timeline ne porta solo l'anteprima. */
  const recordFor = (event) => {
    const source = { visit: visits, exam: exams, treatment: treatments, vaccine: vaccines }[
      event.kind
    ];
    return source?.find((r) => r.id === event.sourceId) || null;
  };

  const events = useMemo(
    () => buildTimeline({ visits, exams, treatments, vaccines, locale }),
    [visits, exams, treatments, vaccines, locale]
  );

  const years = useMemo(
    () => [...new Set(events.map((e) => new Date(e.date).getFullYear()))].sort((a, b) => b - a),
    [events]
  );

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return events.filter((e) => {
      if (kinds.length > 0 && !kinds.includes(e.kind)) return false;
      if (year && new Date(e.date).getFullYear() !== year) return false;
      if (!q) return true;
      return [e.title, e.subtitle, label(timelineKindInfo(e.kind), locale)]
        .filter(Boolean)
        .some((v) => v.toLowerCase().includes(q));
    });
  }, [events, kinds, year, search, locale]);

  /** Anno → mese, dal più recente, come `filteredByYear` su iOS. */
  const grouped = useMemo(() => {
    const byYear = new Map();
    for (const e of filtered) {
      const d = new Date(e.date);
      const y = d.getFullYear();
      const m = d.getMonth();
      if (!byYear.has(y)) byYear.set(y, new Map());
      const months = byYear.get(y);
      months.set(m, [...(months.get(m) || []), e]);
    }
    return [...byYear.entries()]
      .sort((a, b) => b[0] - a[0])
      .map(([y, months]) => ({
        year: y,
        count: [...months.values()].reduce((n, list) => n + list.length, 0),
        months: [...months.entries()]
          .sort((a, b) => b[0] - a[0])
          .map(([m, list]) => ({ month: m, events: list })),
      }));
  }, [filtered]);

  const monthName = (month) =>
    new Date(2000, month, 1).toLocaleDateString(localeTag(locale), { month: "long" });

  const toggleKind = (raw) =>
    setKinds((current) =>
      current.includes(raw) ? current.filter((k) => k !== raw) : [...current, raw]
    );

  return (
    <div className="sa-page">
      <ModuleHeader title={s.title} onBack={onBack} backLabel={h.back} />

      <div className="sa-filters">
        <input
          className="sa-search"
          placeholder={s.searchPlaceholder}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select
          className="sa-chip"
          value={year ?? ""}
          onChange={(e) => setYear(e.target.value ? Number(e.target.value) : null)}
        >
          <option value="">{s.allYears}</option>
          {years.map((y) => (
            <option key={y} value={y}>
              {y}
            </option>
          ))}
        </select>
        {TIMELINE_KINDS.map((k) => {
          const on = kinds.includes(k.raw);
          return (
            <button
              key={k.raw}
              className={"sa-chip" + (on ? " on" : "")}
              style={on ? { background: k.color } : undefined}
              onClick={() => toggleKind(k.raw)}
            >
              {k.emoji} {label(k, locale)}
            </button>
          );
        })}
      </div>

      {grouped.length === 0 ? (
        <p className="pw-empty">{events.length === 0 ? s.empty : h.noResults}</p>
      ) : (
        grouped.map((group) => (
          <div key={group.year}>
            <div className="sa-year">
              <strong>{group.year}</strong>
              <span>{s.eventCount(group.count)}</span>
            </div>
            {group.months.map((m) => (
              <div key={m.month}>
                <div className="sa-month">{monthName(m.month)}</div>
                <ul className="sa-list">
                  {m.events.map((e) => {
                    const info = timelineKindInfo(e.kind);
                    return (
                      <li key={e.id} className="sa-item">
                        <span className="sa-item-dot" style={{ background: info.color }} />
                        <button
                          className="sa-item-body sa-item-open"
                          onClick={() => setOpenEvent(e)}
                        >
                          <span className="sa-item-title">
                            {info.emoji} {e.title}
                          </span>
                          <span className="sa-item-meta">
                            {[fmtDate(e.date, locale), label(info, locale), e.subtitle]
                              .filter(Boolean)
                              .join(" · ")}
                          </span>
                        </button>
                      </li>
                    );
                  })}
                </ul>
              </div>
            ))}
          </div>
        ))
      )}

      {openEvent && (
        <div className="pw-detail-overlay" onClick={() => setOpenEvent(null)}>
          <aside className="pw-detail" onClick={(e) => e.stopPropagation()}>
            <header>
              <h2>
                {timelineKindInfo(openEvent.kind).emoji} {openEvent.title}
              </h2>
              <button onClick={() => setOpenEvent(null)}>✕</button>
            </header>
            <EventDetail
              kind={openEvent.kind}
              record={recordFor(openEvent)}
              h={h}
              locale={locale}
            />
          </aside>
        </div>
      )}
    </div>
  );
}

/**
 * Dettaglio dell'evento, con i campi del record vero. Un evento può puntare a
 * un record appena eliminato da un altro dispositivo: in quel caso si dice, non
 * si mostra un pannello vuoto.
 */
function EventDetail({ kind, record, h, locale }) {
  if (!record) return <p className="pw-hint">{h.timeline.recordGone}</p>;

  if (kind === "visit") {
    const v = h.visits;
    return (
      <>
        <DetailRow label={v.date} value={fmtDate(record.date, locale)} />
        <DetailRow label={v.doctor} value={record.doctorName} />
        <DetailRow label={v.specialization} value={record.doctorSpecialization} />
        <DetailRow
          label={v.status}
          value={label(visitStatusInfo(record.visitStatus), locale)}
        />
        <DetailRow label={v.reason} value={record.reason} />
        <DetailRow label={v.diagnosis} value={record.diagnosis} />
        <DetailRow label={v.recommendations} value={record.recommendations} />
        <DetailRow label={v.therapies} value={record.therapyTypes.join(", ")} />
        <DetailRow
          label={v.prescribedExams}
          value={record.prescribedExams
            .map((e) => `${e.name}${e.isUrgent ? " ⚠️" : ""}`)
            .join(", ")}
        />
        <DetailRow
          label={v.asNeededDrugs}
          value={record.asNeededDrugs
            .map((d) => `${d.drugName} ${d.dosageValue ?? ""} ${d.dosageUnit ?? ""}`.trim())
            .join(", ")}
        />
        <DetailRow label={v.notes} value={record.notes} />
        <DetailRow
          label={v.cost}
          value={record.cost != null ? `€ ${record.cost.toFixed(2)}` : null}
        />
        <DetailRow
          label={v.nextVisit}
          value={
            record.nextVisitDate
              ? [fmtDate(record.nextVisitDate, locale), record.nextVisitReason]
                  .filter(Boolean)
                  .join(" — ")
              : null
          }
        />
      </>
    );
  }

  if (kind === "exam") {
    const x = h.exams;
    return (
      <>
        <DetailRow label={x.status} value={label(examStatusInfo(record.statusRaw), locale)} />
        <DetailRow label={x.urgent} value={record.isUrgent ? "✓" : null} />
        <DetailRow label={x.deadline} value={fmtDate(record.deadline, locale)} />
        <DetailRow label={x.location} value={record.location} />
        <DetailRow label={x.preparation} value={record.preparation} />
        <DetailRow label={x.notes} value={record.notes} />
        <DetailRow
          label={x.cost}
          value={record.cost != null ? `€ ${record.cost.toFixed(2)}` : null}
        />
        <DetailRow label={x.resultDate} value={fmtDate(record.resultDate, locale)} />
        <DetailRow label={x.result} value={record.resultText} />
      </>
    );
  }

  if (kind === "treatment") {
    const c = h.treatments;
    return (
      <>
        <DetailRow label={c.drugName} value={record.drugName} />
        <DetailRow label={c.activeIngredient} value={record.activeIngredient} />
        <DetailRow label={c.dosage} value={`${record.dosageValue} ${record.dosageUnit}`} />
        <DetailRow label={c.dailyFrequency} value={frequencyLabel(record, locale)} />
        <DetailRow label={c.startDate} value={fmtDate(record.startDate, locale)} />
        <DetailRow label={c.endDate} value={fmtDate(record.endDate, locale)} />
        <DetailRow
          label={c.durationDays}
          value={record.isLongTerm ? c.longTerm : c.days(record.durationDays)}
        />
        <DetailRow label={c.scheduleTimes} value={record.scheduleTimes.join(", ")} />
        <DetailRow label={c.notes} value={record.notes} />
      </>
    );
  }

  const w = h.vaccines;
  const site = ADMINISTRATION_SITES.find((s) => s.raw === record.administrationSiteRaw);
  return (
    <>
      <DetailRow label={w.type} value={label(vaccineTypeInfo(record.vaccineTypeRaw), locale)} />
      <DetailRow label={w.status} value={label(vaccineStatusInfo(record.statusRaw), locale)} />
      <DetailRow label={w.commercialName} value={record.commercialName} />
      <DetailRow
        label={w.doseNumber}
        value={record.totalDoses > 1 ? `${record.doseNumber}/${record.totalDoses}` : null}
      />
      <DetailRow label={w.administeredDate} value={fmtDate(vaccineDate(record), locale)} />
      <DetailRow label={w.nextDose} value={fmtDate(record.nextDoseDate, locale)} />
      <DetailRow label={w.lot} value={record.lotNumber} />
      <DetailRow label={w.administeredBy} value={record.administeredBy} />
      <DetailRow label={w.site} value={site ? label(site, locale) : null} />
      <DetailRow label={w.notes} value={record.notes} />
    </>
  );
}
