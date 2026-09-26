import { useTranslation } from "../i18n/LocaleContext";
import Modal from "./Modal";

/**
 * Un evento di un calendario iscritto: sola lettura, con «Copia in KidBox»
 * per aggiungerci promemoria e visibilità. Come la scheda di iOS e Android.
 */
export default function FeedEventModal({ event, onCopy, onClose }) {
  const { t, locale } = useTranslation();
  const tf = t.calendar.feeds;
  const lang = locale === "en" ? "en-US" : locale;
  const start = event.startDate.toDate();
  const end = event.endDate.toDate();
  const day = new Intl.DateTimeFormat(lang, { weekday: "long", day: "numeric", month: "long" });
  const hm = new Intl.DateTimeFormat(lang, { hour: "2-digit", minute: "2-digit" });
  const sameDay = start.toDateString() === end.toDateString();
  let when;
  if (event.isAllDay) {
    when = sameDay ? day.format(start) : `${day.format(start)} – ${day.format(end)}`;
  } else if (sameDay) {
    when = `${day.format(start)}, ${hm.format(start)} – ${hm.format(end)}`;
  } else {
    when = `${day.format(start)} ${hm.format(start)} – ${day.format(end)} ${hm.format(end)}`;
  }

  return (
    <Modal onClose={onClose}>
      <div className="modal-header">
        <button className="modal-icon-btn" onClick={onClose}>✕</button>
      </div>
      <div className="modal-label">{tf.eventTitle}</div>
      <div className="modal-title">{event.title || tf.untitled}</div>
      <p className="modal-hint">{when.charAt(0).toUpperCase() + when.slice(1)}</p>
      <p className="modal-hint">
        <span className="feed-dot" style={{ background: event._feed.colorHex }} /> {event._feed.name}
      </p>
      {event.location && <p className="modal-hint">📍 {event.location}</p>}
      <button className="modal-save-btn feed-copy-btn" onClick={onCopy}>
        {tf.copy}
      </button>
      <p className="modal-hint">{tf.eventFooter.replace("%s", event._feed.name)}</p>
      {event.notes && (
        <>
          <div className="modal-label">{t.calendar.notes}</div>
          <p className="feed-notes">{event.notes}</p>
        </>
      )}
    </Modal>
  );
}
