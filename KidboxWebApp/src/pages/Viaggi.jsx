import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { useFamily } from "../FamilyContext";
import { useTranslation } from "../i18n/LocaleContext";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { useChildren } from "../hooks/useChildren";
import {
  PACKING_CATEGORIES,
  deleteTrip,
  listenTripContent,
  listenTrips,
  packingInfo,
  setPackingItemChecked,
  transportInfo,
  tripPhase,
} from "../services/trips";
import {
  buildOverview,
  dayCountBetween,
  formatMoney,
  primaryDestination,
  travelerNames,
} from "../services/travelItinerary";
import { placeImageURL } from "../services/travelPlaceImage";
import "./Viaggi.css";

/* ── Copertina ───────────────────────────────────────────────────────────── */

/** Gradiente stabile per destinazione: la stessa meta ha sempre gli stessi colori. */
const COVER_GRADIENTS = [
  ["#1F8CD1", "#33C7E6"],
  ["#E8833A", "#F2BF1A"],
  ["#8C59D9", "#C471ED"],
  ["#2E9E6B", "#7BD389"],
  ["#D9455F", "#F2795B"],
  ["#3B5BA5", "#6C8EE3"],
];

function gradientFor(seed) {
  let hash = 0;
  for (let i = 0; i < seed.length; i += 1) hash = (hash * 31 + seed.charCodeAt(i)) >>> 0;
  const [from, to] = COVER_GRADIENTS[hash % COVER_GRADIENTS.length];
  return `linear-gradient(135deg, ${from}, ${to})`;
}

function TripCover({ destination, children, tall }) {
  const [imageURL, setImageURL] = useState(null);

  useEffect(() => {
    let cancelled = false;
    setImageURL(null);
    placeImageURL(destination).then((url) => {
      if (!cancelled) setImageURL(url);
    });
    return () => {
      cancelled = true;
    };
  }, [destination]);

  return (
    <span
      className={"vg-cover" + (tall ? " tall" : "")}
      style={{
        backgroundImage: imageURL
          ? `url("${imageURL}")`
          : gradientFor(destination || "kidbox"),
      }}
    >
      <span className="vg-cover-shade" />
      <span className="vg-cover-body">{children}</span>
    </span>
  );
}

/* ── Pagina ──────────────────────────────────────────────────────────────── */

export default function Viaggi() {
  const { currentFamilyId } = useFamily();
  const { t, locale } = useTranslation();
  const v = t.travel;
  const isEn = locale === "en";
  const members = useFamilyMembers(currentFamilyId);
  const children = useChildren(currentFamilyId);

  const [trips, setTrips] = useState([]);
  const [content, setContent] = useState(null);
  const [selectedId, setSelectedId] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    return listenTrips({
      familyId: currentFamilyId,
      onChange: setTrips,
      onError: (err) => setError(err.message),
    });
  }, [currentFamilyId]);

  useEffect(() => {
    if (!currentFamilyId || !selectedId) {
      setContent(null);
      return undefined;
    }
    return listenTripContent({
      familyId: currentFamilyId,
      tripId: selectedId,
      onChange: setContent,
      onError: (err) => setError(err.message),
    });
  }, [currentFamilyId, selectedId]);

  const selected = trips.find((trip) => trip.id === selectedId) || null;

  /* ── Formattazione ─────────────────────────────────────────────────────── */

  const dateLocale = isEn ? "en-US" : "it-IT";

  const fmtDay = (millis, opts) => new Date(millis).toLocaleDateString(dateLocale, opts);

  /** `TravelTripDateRangeFormatter`: si ripete solo ciò che cambia. */
  const dateRange = (start, end) => {
    const a = new Date(start);
    const b = new Date(end);
    const full = { day: "numeric", month: "short", year: "numeric" };
    if (a.toDateString() === b.toDateString()) return fmtDay(start, full);
    if (a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth()) {
      return `${a.getDate()} – ${b.getDate()} ${fmtDay(end, { month: "short", year: "numeric" })}`;
    }
    if (a.getFullYear() === b.getFullYear()) {
      return `${fmtDay(start, { day: "numeric", month: "short" })} – ${fmtDay(end, full)}`;
    }
    return `${fmtDay(start, full)} – ${fmtDay(end, full)}`;
  };

  const isoDate = (dateString) => {
    const parsed = new Date(`${dateString}T00:00:00`);
    return Number.isNaN(parsed.getTime())
      ? dateString
      : parsed.toLocaleDateString(dateLocale, { day: "numeric", month: "long", year: "numeric" });
  };

  const formatAge = (birthMillis) => {
    if (!birthMillis) return "";
    const birth = new Date(birthMillis);
    const now = new Date();
    let months =
      (now.getFullYear() - birth.getFullYear()) * 12 + (now.getMonth() - birth.getMonth());
    if (now.getDate() < birth.getDate()) months -= 1;
    const years = Math.floor(months / 12);
    if (years > 0) return v.years(years);
    if (months > 0) return v.months(months);
    return v.newborn;
  };

  const money = (value) => formatMoney(value, selected?.currency);

  /* ── Vista del viaggio aperto ──────────────────────────────────────────── */

  const overview = useMemo(() => {
    if (!selected || !content) return null;
    return buildOverview({
      trip: selected,
      dayPlans: content.dayPlans,
      legs: content.legs,
      syntheticText: {
        morning: (place, day) => (day === 1 ? v.syntheticArrival(place) : v.syntheticMorning(place)),
        afternoon: (place) => v.syntheticAfternoon(place),
        evening: (place) => v.syntheticEvening(place),
      },
    });
  }, [selected, content, v]);

  const travelers = useMemo(() => {
    if (!selected) return [];
    return travelerNames({
      participantIdsJson: selected.participantIdsJson,
      members,
      children,
      formatAge,
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selected, members, children, locale]);

  const packingByCategory = useMemo(() => {
    const map = new Map();
    for (const item of content?.packingItems || []) {
      map.set(item.category, [...(map.get(item.category) || []), item]);
    }
    return map;
  }, [content]);

  const packingDone = (content?.packingItems || []).filter((i) => i.isChecked).length;

  const togglePacking = async (item) => {
    try {
      await setPackingItemChecked({
        familyId: currentFamilyId,
        tripId: selectedId,
        itemId: item.id,
        isChecked: !item.isChecked,
      });
    } catch (err) {
      setError(err.message);
    }
  };

  const removeTrip = async () => {
    if (!window.confirm(v.confirmDelete)) return;
    try {
      await deleteTrip({ familyId: currentFamilyId, tripId: selectedId });
      setSelectedId(null);
    } catch (err) {
      setError(err.message);
    }
  };

  const label = (info) => (isEn ? info.en : info.it);

  /* ── Render ────────────────────────────────────────────────────────────── */

  return (
    <div className="vg-page">
      <header className="pw-header">
        <h1>{v.title}</h1>
        <p className="vg-hint">{v.plannedInApp}</p>
      </header>

      {error && <p className="error">{error}</p>}

      {trips.length === 0 ? (
        <p className="pw-empty">{v.empty}</p>
      ) : (
        <div className="vg-grid">
          {trips.map((trip) => {
            const phase = tripPhase(trip);
            const days = dayCountBetween(trip.startDate, trip.endDate);
            return (
              <button key={trip.id} className="vg-card" onClick={() => setSelectedId(trip.id)}>
                <TripCover destination={primaryDestination(trip.name)}>
                  <span className="vg-card-name">{trip.name}</span>
                  <span className="vg-card-dates">{dateRange(trip.startDate, trip.endDate)}</span>
                </TripCover>
                <span className="vg-card-foot">
                  <span className="vg-status" style={{ background: phase.color }}>
                    {label(phase)}
                  </span>
                  <span className="vg-card-days">{v.days(days)}</span>
                </span>
              </button>
            );
          })}
        </div>
      )}

      {selected && (
        <div className="pw-detail-overlay" onClick={() => setSelectedId(null)}>
          <aside className="vg-detail" onClick={(e) => e.stopPropagation()}>
            <TripCover destination={primaryDestination(selected.name, content?.legs || [])} tall>
              <span className="vg-detail-title">
                {overview?.destinationTitle || selected.name}
              </span>
              <span className="vg-detail-sub">
                {[
                  dateRange(selected.startDate, selected.endDate),
                  v.days(dayCountBetween(selected.startDate, selected.endDate)),
                  travelers.length ? travelers.join(", ") : v.family,
                ].join(" · ")}
              </span>
            </TripCover>

            <button className="vg-close" onClick={() => setSelectedId(null)} aria-label={v.close}>
              ✕
            </button>

            <div className="vg-detail-body">
              {!content ? (
                <p className="pw-hint">{v.loading}</p>
              ) : (
                <>
                  {overview?.summary && <p className="vg-summary">{overview.summary}</p>}

                  <section className="vg-budget">
                    <span className="vg-budget-label">{v.estimatedTotal}</span>
                    <span className="vg-budget-value">
                      {money(overview.estimatedTotal)}
                      <em>{v.ofBudget(money(overview.budgetLimit))}</em>
                    </span>
                  </section>

                  <div className="vg-budget-grid">
                    {[
                      { emoji: "🛏️", name: v.hotels, value: overview.budget.hotels },
                      { emoji: "✈️", name: v.flights, value: overview.budget.flights },
                      { emoji: "🍽️", name: v.restaurants, value: overview.budget.restaurants },
                      { emoji: "🎯", name: v.activities, value: overview.budget.activities },
                    ].map((row) => (
                      <span key={row.name} className="vg-budget-cell">
                        <span className="vg-budget-emoji">{row.emoji}</span>
                        <span className="vg-budget-name">{row.name}</span>
                        <span className="vg-budget-amount">{money(row.value)}</span>
                      </span>
                    ))}
                  </div>

                  {content.legs.length > 0 && (
                    <section>
                      <h3 className="vg-section">{v.legs}</h3>
                      <ul className="vg-legs">
                        {content.legs.map((leg) => {
                          const mode = transportInfo(leg.transportMode);
                          return (
                            <li key={leg.id}>
                              <span className="vg-leg-mode">{mode.emoji}</span>
                              <span className="vg-leg-body">
                                <span className="vg-leg-route">
                                  {leg.fromLocation} → {leg.toLocation}
                                </span>
                                <span className="vg-leg-meta">
                                  {[label(mode), leg.notes].filter(Boolean).join(" · ")}
                                </span>
                              </span>
                            </li>
                          );
                        })}
                      </ul>
                    </section>
                  )}

                  <section>
                    <h3 className="vg-section">{v.itinerary(overview.dayCount)}</h3>
                    {overview.days.every((day) => day.blocks.length === 0) ? (
                      <p className="pw-hint">{v.noItinerary}</p>
                    ) : (
                      overview.days.map((day) => (
                        <article key={day.id} className="vg-day">
                          <header className="vg-day-head">
                            <span>
                              <span className="vg-day-title">
                                {day.location
                                  ? day.dayIndex === 1
                                    ? v.arrivalTo(day.location)
                                    : day.location
                                  : v.dayN(day.dayIndex)}
                              </span>
                              {day.dateString && (
                                <span className="vg-day-date">{isoDate(day.dateString)}</span>
                              )}
                            </span>
                            {day.dayCost != null && (
                              <span className="vg-day-cost">{money(day.dayCost)}</span>
                            )}
                          </header>

                          {day.blocks.map((block) => (
                            <div key={block.period} className="vg-block">
                              <div className="vg-block-head">
                                <span className="vg-dot" style={{ background: block.color }} />
                                <span className="vg-block-title">
                                  {v.periods[block.period]} · {v.stops(block.stops.length)}
                                </span>
                                <span className="vg-block-meta">
                                  {[
                                    block.durationSummary,
                                    block.costSummary === "" ? null : `~${money(block.costSummary)}`,
                                  ]
                                    .filter(Boolean)
                                    .join(" · ")}
                                </span>
                              </div>
                              <ul className="vg-stops">
                                {block.stops.map((stop, index) => (
                                  <li key={`${block.period}-${index}`}>
                                    <span className="vg-stop-time">{stop.time}</span>
                                    <span className="vg-stop-emoji">{stop.emoji}</span>
                                    <span className="vg-stop-body">
                                      <span className="vg-stop-title">{stop.title}</span>
                                      {stop.detail && (
                                        <span className="vg-stop-detail">{stop.detail}</span>
                                      )}
                                    </span>
                                  </li>
                                ))}
                              </ul>
                            </div>
                          ))}

                          {(day.accommodationName || day.weatherBackupPlan) && (
                            <div className="vg-day-extra">
                              {day.accommodationName && (
                                <span>
                                  🏨 {day.accommodationName}
                                  {day.accommodationCostPerNight
                                    ? ` · ${v.perNight(money(day.accommodationCostPerNight))}`
                                    : ""}
                                </span>
                              )}
                              {day.weatherBackupPlan && (
                                <span>🌧️ {day.weatherBackupPlan}</span>
                              )}
                            </div>
                          )}
                        </article>
                      ))
                    )}
                  </section>

                  <section>
                    <h3 className="vg-section">
                      {v.packing}
                      {content.packingItems.length > 0 && (
                        <span className="vg-packing-count">
                          {v.packingDone(packingDone, content.packingItems.length)}
                        </span>
                      )}
                    </h3>
                    {content.packingItems.length === 0 ? (
                      <p className="pw-hint">{v.packingEmpty}</p>
                    ) : (
                      PACKING_CATEGORIES.filter((c) => packingByCategory.has(c.raw)).map((c) => (
                        <div key={c.raw} className="vg-packing-group">
                          <span className="vg-packing-cat">
                            {c.emoji} {label(packingInfo(c.raw))}
                          </span>
                          {packingByCategory.get(c.raw).map((item) => (
                            <label key={item.id} className="vg-packing-item">
                              <input
                                type="checkbox"
                                checked={item.isChecked}
                                onChange={() => togglePacking(item)}
                              />
                              <span className={item.isChecked ? "checked" : ""}>{item.label}</span>
                              {item.fromMedicalProfile && <span title={v.fromMedical}>❤️</span>}
                            </label>
                          ))}
                        </div>
                      ))
                    )}
                  </section>

                  <section>
                    <h3 className="vg-section">{v.linked}</h3>
                    <div className="vg-linked">
                      <Link className="vg-link" to="/foto">
                        📷 {v.album}
                        <em>{v.albumTitle(selected.name)}</em>
                      </Link>
                      <Link className="vg-link" to="/note">
                        📝 {v.note}
                        <em>{selected.name}</em>
                      </Link>
                      <Link className="vg-link" to="/todo">
                        ✅ {v.todoList}
                        <em>{selected.name}</em>
                      </Link>
                    </div>
                  </section>

                  <button className="vg-delete" onClick={removeTrip}>
                    🗑 {v.delete}
                  </button>
                </>
              )}
            </div>
          </aside>
        </div>
      )}
    </div>
  );
}
