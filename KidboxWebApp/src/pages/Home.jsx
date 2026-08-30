import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import { useFamilyCollection } from "../hooks/useFamilyCollection";
import { useChildren } from "../hooks/useChildren";
import { setHeroPhoto } from "../services/familyHeroPhoto";
import { loadFamilyKey } from "../services/familyKey";
import { readField } from "../services/noteCrypto";
import { noteHtmlToText } from "../services/noteHtml";
import { categoryFromId, formatAmount } from "../expenseCategories";
import { categoryInfo } from "../calendarUtils";
import { listenSharedLocations } from "../services/location";
import "./Home.css";

/** Riquadro con intestazione cliccabile e fino a quattro righe di anteprima. */
function Widget({ icon, title, badge, onOpen, children, empty }) {
  const { t } = useTranslation();
  return (
    <section className="widget">
      <button className="widget-head" onClick={onOpen}>
        <span className="widget-icon">{icon}</span>
        <span className="widget-title">{title}</span>
        {badge != null && <span className="widget-badge">{badge}</span>}
        <span className="widget-more">{t.home.dashboard.seeAll} ›</span>
      </button>
      <div className="widget-body">
        {empty ? <p className="widget-empty">{t.home.dashboard.nothing}</p> : children}
      </div>
    </section>
  );
}

export default function Home() {
  const { currentFamily, currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();
  const navigate = useNavigate();
  const fileInputRef = useRef(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const children = useChildren(currentFamilyId);
  const childId = children[0]?.id ?? "";

  const { items: events } = useFamilyCollection(currentFamilyId, "calendarEvents");
  const { items: todos } = useFamilyCollection(currentFamilyId, "todos");
  const { items: groceries } = useFamilyCollection(currentFamilyId, "groceries");
  const { items: rawNotes } = useFamilyCollection(currentFamilyId, "notes");
  const { items: expenses } = useFamilyCollection(currentFamilyId, "expenses");
  const { items: photos } = useFamilyCollection(currentFamilyId, "photos");

  const [notePreviews, setNotePreviews] = useState([]);
  const [notesLocked, setNotesLocked] = useState(false);
  const [sharingCount, setSharingCount] = useState(0);

  const dateLabel = new Date().toLocaleDateString(locale === "en" ? "en-US" : "it-IT", {
    weekday: "long",
    day: "numeric",
    month: "long",
  });

  /* ── Hero ─────────────────────────────────────────────────────────── */
  const heroUrl = currentFamily?.heroPhotoURL || null;
  const heroStyle = heroUrl
    ? {
        backgroundImage: `url(${heroUrl})`,
        transform: `translate(${currentFamily?.heroPhotoOffsetX ?? 0}px, ${
          currentFamily?.heroPhotoOffsetY ?? 0
        }px) scale(${currentFamily?.heroPhotoScale ?? 1})`,
      }
    : null;

  const onPickFile = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    setBusy(true);
    setError(null);
    try {
      await setHeroPhoto({
        familyId: currentFamilyId,
        file,
        uid: user.uid,
        crop: {
          scale: currentFamily?.heroPhotoScale ?? 1,
          offsetX: currentFamily?.heroPhotoOffsetX ?? 0,
          offsetY: currentFamily?.heroPhotoOffsetY ?? 0,
        },
      });
    } catch (err) {
      setError(`${t.home.uploadFailed}: ${err.message}`);
    } finally {
      setBusy(false);
    }
  };

  /* ── Dati dei widget ──────────────────────────────────────────────── */

  const upcoming = useMemo(() => {
    const now = Date.now();
    return events
      .filter((e) => (e.endDate?.toMillis?.() ?? e.startDate?.toMillis?.() ?? 0) >= now)
      .sort((a, b) => (a.startDate?.toMillis?.() ?? 0) - (b.startDate?.toMillis?.() ?? 0))
      .slice(0, 4);
  }, [events]);

  const openTodos = useMemo(
    () =>
      todos
        .filter((x) => x.childId === childId && !x.isDone)
        .sort((a, b) => {
          // Prima chi ha una scadenza, poi per data: in home conta cosa scade prima.
          const da = a.dueAt?.toMillis?.() ?? Infinity;
          const db2 = b.dueAt?.toMillis?.() ?? Infinity;
          return da - db2;
        }),
    [todos, childId]
  );

  const toBuy = useMemo(() => groceries.filter((g) => !g.isPurchased), [groceries]);

  const recentExpenses = useMemo(
    () =>
      [...expenses]
        .sort((a, b) => (b.date?.toMillis?.() ?? 0) - (a.date?.toMillis?.() ?? 0))
        .slice(0, 4),
    [expenses]
  );

  const monthTotal = useMemo(() => {
    const now = new Date();
    return expenses
      .filter((e) => {
        const d = e.date?.toDate?.();
        return d && d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear();
      })
      .reduce((sum, e) => sum + (Number(e.amount) || 0), 0);
  }, [expenses]);

  const recentPhotos = useMemo(
    () =>
      [...photos]
        .sort((a, b) => (b.takenAt?.toMillis?.() ?? 0) - (a.takenAt?.toMillis?.() ?? 0))
        // Tre, quante le righe di anteprima delle altre card.
        .slice(0, 3),
    [photos]
  );

  // Le note sono cifrate: si decifrano solo le quattro da mostrare, non tutte.
  useEffect(() => {
    let cancelled = false;
    if (!currentFamilyId || !user || rawNotes.length === 0) {
      setNotePreviews([]);
      return undefined;
    }
    const latest = [...rawNotes]
      .sort((a, b) => (b.updatedAt?.toMillis?.() ?? 0) - (a.updatedAt?.toMillis?.() ?? 0))
      .slice(0, 3);

    loadFamilyKey({ familyId: currentFamilyId, userId: user.uid })
      .then(async (key) => {
        const decoded = await Promise.all(
          latest.map(async (n) => ({
            id: n.id,
            title: await readField(n.titleEnc, n.title, key),
            body: noteHtmlToText(await readField(n.bodyEnc, n.body, key)),
          }))
        );
        if (!cancelled) {
          setNotePreviews(decoded);
          setNotesLocked(false);
        }
      })
      .catch(() => {
        if (!cancelled) setNotesLocked(true);
      });
    return () => {
      cancelled = true;
    };
  }, [rawNotes, currentFamilyId, user]);

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    return listenSharedLocations({
      familyId: currentFamilyId,
      onChange: (people) => setSharingCount(people.length),
      onError: () => setSharingCount(0),
    });
  }, [currentFamilyId]);

  const fmtDay = (date) =>
    date
      ? new Intl.DateTimeFormat(locale === "en" ? "en-US" : "it-IT", {
          day: "2-digit",
          month: "2-digit",
          hour: "2-digit",
          minute: "2-digit",
        }).format(date)
      : "";

  return (
    <div>
      <div className="hero-card">
        {heroStyle ? (
          <div className="hero-photo" style={heroStyle} />
        ) : (
          <div className="hero-photo hero-photo-empty" />
        )}
        <div className="hero-scrim" />
        <div className="hero-top">
          <span className="hero-date">{dateLabel}</span>
          <span className="hero-badge">
            {t.home.membersCount(currentFamily?.memberCount ?? 0)}
          </span>
        </div>
        <div className="hero-bottom">
          <div className="hero-title">{currentFamily?.name || "…"}</div>
          <button
            className="hero-change-btn"
            disabled={busy || !currentFamilyId}
            onClick={() => fileInputRef.current?.click()}
          >
            🖼 {busy ? t.home.uploading : t.home.changePhoto}
          </button>
        </div>
        <input ref={fileInputRef} type="file" accept="image/*" hidden onChange={onPickFile} />
      </div>

      {error && <p className="error">{error}</p>}

      <div className="dashboard">
        <Widget
          icon="📅"
          title={t.home.dashboard.upcoming}
          onOpen={() => navigate("/calendario")}
          empty={upcoming.length === 0}
        >
          <ul className="w-list">
            {upcoming.map((e) => {
              const cat = categoryInfo(e.categoryRaw);
              return (
                <li key={e.id}>
                  <span className="w-dot" style={{ background: cat.color }} />
                  <span className="w-main">{e.title}</span>
                  <span className="w-meta">{fmtDay(e.startDate?.toDate?.())}</span>
                </li>
              );
            })}
          </ul>
        </Widget>

        <Widget
          icon="✅"
          title={t.home.dashboard.todos}
          badge={openTodos.length || null}
          onOpen={() => navigate("/todo")}
          empty={openTodos.length === 0}
        >
          <ul className="w-list">
            {openTodos.slice(0, 4).map((x) => (
              <li key={x.id}>
                <span className="w-circle">○</span>
                <span className="w-main">{x.title}</span>
                {x.dueAt && <span className="w-meta">{fmtDay(x.dueAt.toDate())}</span>}
              </li>
            ))}
          </ul>
        </Widget>

        <Widget
          icon="🛒"
          title={t.home.dashboard.grocery}
          badge={toBuy.length || null}
          onOpen={() => navigate("/spesa")}
          empty={toBuy.length === 0}
        >
          <ul className="w-list">
            {toBuy.slice(0, 4).map((g) => (
              <li key={g.id}>
                <span className="w-circle">○</span>
                <span className="w-main">{g.name}</span>
                {g.category && <span className="w-meta">{g.category}</span>}
              </li>
            ))}
          </ul>
        </Widget>

        <Widget
          icon="📝"
          title={t.home.dashboard.notes}
          onOpen={() => navigate("/note")}
          empty={notePreviews.length === 0 && !notesLocked}
        >
          {notesLocked ? (
            <p className="widget-empty">🔒 {t.home.dashboard.locked}</p>
          ) : (
            <ul className="w-list w-notes">
              {notePreviews.map((n) => (
                <li key={n.id}>
                  <span className="w-main">
                    <strong>{n.title.trim() || t.notes.untitled}</strong>
                    {/* Nessun taglio a mano: alla larghezza ci pensa il CSS, che
                        tronca dove finisce la card e mette i puntini. */}
                    <span className="w-sub">{n.body}</span>
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Widget>

        <Widget
          icon="💶"
          title={t.home.dashboard.expenses}
          badge={monthTotal > 0 ? formatAmount(monthTotal, locale) : null}
          onOpen={() => navigate("/spese")}
          empty={recentExpenses.length === 0}
        >
          <ul className="w-list">
            {recentExpenses.map((e) => {
              const cat = categoryFromId(currentFamilyId, e.categoryId);
              return (
                <li key={e.id}>
                  <span className="w-emoji">{cat?.icon ?? "•"}</span>
                  <span className="w-main">{e.title}</span>
                  <span className="w-meta strong">{formatAmount(e.amount, locale)}</span>
                </li>
              );
            })}
          </ul>
        </Widget>

        <Widget
          icon="📷"
          title={t.home.dashboard.photos}
          onOpen={() => navigate("/foto")}
          empty={recentPhotos.length === 0}
        >
          <div className="w-photos">
            {recentPhotos.map((p) =>
              p.thumbnailBase64 ? (
                <img
                  key={p.id}
                  src={`data:image/jpeg;base64,${p.thumbnailBase64}`}
                  alt=""
                  loading="lazy"
                />
              ) : (
                <span key={p.id} className="w-photo-ph">
                  🖼
                </span>
              )
            )}
          </div>
        </Widget>

        <Widget
          icon="📍"
          title={t.home.dashboard.sharing}
          onOpen={() => navigate("/posizione")}
          empty={false}
        >
          <p className="w-location">
            {sharingCount > 0
              ? `● ${t.home.dashboard.sharingNow(sharingCount)}`
              : t.home.dashboard.noSharing}
          </p>
        </Widget>
      </div>
    </div>
  );
}
