import { useState } from "react";
import { httpsCallable } from "firebase/functions";
import { functions } from "../firebase";
import { useTranslation } from "../i18n/LocaleContext";
import { FEED_PALETTE } from "../hooks/useCalendarFeeds";
import Modal from "./Modal";

/**
 * I calendari iscritti da link (feed ICS): elenco, iscrizione, rimozione.
 * Il documento lo scrive solo il server (le rules lo lasciano in lettura):
 * si passa da `saveCalendarFeed` / `deleteCalendarFeed`, che scarica subito il
 * link, così chi ne incolla uno sbagliato lo sa adesso e non tra sei ore.
 * Sul web non esistono i calendari del telefono: questa è l'unica strada.
 */
function hostOf(raw) {
  try {
    return new URL(raw.trim().replace(/^webcals?:\/\//i, "https://")).hostname;
  } catch {
    return "";
  }
}

export default function CalendarFeedsModal({ familyId, feeds, onClose }) {
  const { t } = useTranslation();
  const tf = t.calendar.feeds;
  const [adding, setAdding] = useState(false);
  const [url, setUrl] = useState("");
  const [name, setName] = useState("");
  const [color, setColor] = useState(FEED_PALETTE[0]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const reasonText = (reason) => tf.errors[reason] || tf.errors.unreachable;

  const subscribe = async () => {
    if (!url.trim()) return;
    setBusy(true);
    setError(null);
    try {
      await httpsCallable(functions, "saveCalendarFeed")({
        familyId,
        name: name.trim(),
        url: url.trim(),
        colorHex: color,
      });
      setAdding(false);
      setUrl("");
      setName("");
    } catch (err) {
      const reason = err?.details?.reason;
      // Google Calendar respinge (429) le richieste dei server KidBox; le app
      // ripiegano scaricando dal telefono, il browser non può (CORS).
      if (reason === "unreachable" && /(^|\.)google\.com/i.test(hostOf(url))) {
        setError(tf.errors.google_from_app);
      } else {
        setError(reasonText(reason));
      }
    } finally {
      setBusy(false);
    }
  };

  const remove = async (feed) => {
    if (!window.confirm(`${tf.removeTitle.replace("%s", feed.name)}\n\n${tf.removeMessage}`)) return;
    setBusy(true);
    setError(null);
    try {
      await httpsCallable(functions, "deleteCalendarFeed")({ familyId, feedId: feed.id });
    } catch (err) {
      setError(reasonText(err?.details?.reason));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal onClose={busy ? undefined : onClose}>
      <div className="modal-header">
        <button className="modal-icon-btn" onClick={onClose} disabled={busy}>✕</button>
        {adding && (
          <button className="modal-save-btn" disabled={busy || !url.trim()} onClick={subscribe}>
            {tf.subscribe}
          </button>
        )}
      </div>
      <div className="modal-title">{adding ? tf.addTitle : tf.title}</div>
      {error && <p className="error">{error}</p>}

      {adding ? (
        <>
          <input
            className="modal-field"
            type="url"
            placeholder={tf.urlLabel}
            value={url}
            autoFocus
            onChange={(e) => setUrl(e.target.value)}
            disabled={busy}
          />
          <input
            className="modal-field"
            placeholder={tf.nameLabel}
            value={name}
            onChange={(e) => setName(e.target.value)}
            disabled={busy}
          />
          <div className="feed-palette">
            {FEED_PALETTE.map((hex) => (
              <button
                key={hex}
                className={"feed-swatch" + (hex === color ? " selected" : "")}
                style={{ background: hex }}
                onClick={() => setColor(hex)}
                disabled={busy}
                aria-label={hex}
              />
            ))}
          </div>
          {busy && <p className="modal-hint">{tf.loading}</p>}
          <p className="modal-hint">{tf.footer}</p>
        </>
      ) : (
        <>
          <div className="modal-section">
            {feeds.map((feed) => (
              <div key={feed.id} className="modal-row">
                <span className="feed-row-main">
                  <span className="feed-dot" style={{ background: feed.colorHex }} />
                  <span>
                    <span className="feed-name">{feed.name}</span>
                    <span className={"feed-status" + (feed.lastError ? " error" : "")}>
                      {feed.lastError ? tf.statusError : tf.status.replace("%d", feed.eventCount)}
                    </span>
                  </span>
                </span>
                <button className="feed-remove" onClick={() => remove(feed)} disabled={busy}>
                  {tf.remove}
                </button>
              </div>
            ))}
            <div className="modal-row clickable" onClick={() => !busy && setAdding(true)}>
              <span>＋ {tf.add}</span>
            </div>
          </div>
          <p className="modal-hint">{tf.footer}</p>
        </>
      )}
    </Modal>
  );
}
