import { useEffect, useState } from "react";
import { httpsCallable } from "firebase/functions";
import { functions } from "../firebase";
import { useTranslation } from "../i18n/LocaleContext";
import Modal from "./Modal";

/**
 * Il calendario di KidBox dentro Google Calendar, Outlook e il Calendario di
 * Apple: un link iCal personale (functions/calendarExport.js) a cui quei
 * calendari si iscrivono. Personale e non di famiglia perché rispetta la
 * visibilità degli eventi. Sola lettura, e Google lo rilegge quando vuole lui
 * (12-24 ore): il testo lo dice, se no sembra rotto.
 */
const call = (data) => httpsCallable(functions, "calendarExportLink")(data).then((r) => r.data);

function browserTz() {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone;
  } catch {
    return undefined;
  }
}

export default function CalendarExportModal({ familyId, onClose }) {
  const { t } = useTranslation();
  const te = t.calendar.export;
  const [url, setUrl] = useState(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    let alive = true;
    call({ familyId, action: "get" })
      .then((r) => alive && setUrl(r.url))
      .catch(() => alive && setError(te.error))
      .finally(() => alive && setLoading(false));
    return () => {
      alive = false;
    };
  }, [familyId, te.error]);

  const run = async (action, confirmText) => {
    if (confirmText && !window.confirm(confirmText)) return;
    setBusy(true);
    setError(null);
    setCopied(false);
    try {
      const r = await call({ familyId, action, tz: browserTz() });
      setUrl(r.url);
    } catch {
      setError(te.error);
    } finally {
      setBusy(false);
    }
  };

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  };

  const webcal = url ? url.replace(/^https:\/\//, "webcal://") : "";
  const links = url
    ? [
        { key: "google", label: te.google, href: `https://calendar.google.com/calendar/r?cid=${encodeURIComponent(webcal)}` },
        { key: "outlook", label: te.outlook, href: `https://outlook.live.com/calendar/0/addfromweb?url=${encodeURIComponent(url)}&name=KidBox` },
        { key: "outlookWork", label: te.outlookWork, href: `https://outlook.office.com/calendar/0/addfromweb?url=${encodeURIComponent(url)}&name=KidBox` },
        { key: "apple", label: te.apple, href: webcal },
      ]
    : [];

  return (
    <Modal onClose={busy ? undefined : onClose}>
      <div className="modal-header">
        <button className="modal-icon-btn" onClick={onClose} disabled={busy}>✕</button>
      </div>
      <div className="modal-title">{te.title}</div>
      <p className="modal-hint">{te.intro}</p>
      {error && <p className="error">{error}</p>}

      {loading ? (
        <p className="modal-hint">{te.loading}</p>
      ) : url ? (
        <>
          <div className="export-links">
            {links.map((l) => (
              <a key={l.key} className="export-link" href={l.href} target="_blank" rel="noopener noreferrer">
                {l.label} <span aria-hidden="true">↗</span>
              </a>
            ))}
          </div>
          <div className="export-url">
            <input className="modal-field" readOnly value={url} onFocus={(e) => e.target.select()} />
            <button className="modal-save-btn" onClick={copy} disabled={busy}>
              {copied ? te.copied : te.copy}
            </button>
          </div>
          <p className="modal-hint">{te.refresh}</p>
          <p className="modal-hint feed-help-privacy">{te.privacy}</p>
          <div className="export-actions">
            <button className="feed-remove export-secondary" onClick={() => run("rotate", te.rotateConfirm)} disabled={busy}>
              {te.rotate}
            </button>
            <button className="feed-remove" onClick={() => run("disable", te.disableConfirm)} disabled={busy}>
              {te.disable}
            </button>
          </div>
        </>
      ) : (
        <>
          <button className="modal-save-btn feed-copy-btn" onClick={() => run("enable")} disabled={busy}>
            {te.enable}
          </button>
          <p className="modal-hint">{te.refresh}</p>
          <p className="modal-hint feed-help-privacy">{te.privacy}</p>
        </>
      )}
    </Modal>
  );
}
