import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../AuthContext";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { useTranslation } from "../i18n/LocaleContext";
import {
  cancelRequest,
  draftIsEmpty,
  emptyDraft,
  listenOpenRequests,
  listenRequest,
  requestWhen,
  respondToRequest,
  savedShareLink,
} from "../services/requests";
import Modal from "./Modal";
import "./FamilyRequests.css";

/** Nome di un membro per uid, come lo mostra il resto dell'app. */
function useNames(familyId) {
  const { user } = useAuth();
  const { t } = useTranslation();
  const members = useFamilyMembers(familyId);
  const r = t.requests;
  const name = (uid) => {
    if (uid === user?.uid) return r.you;
    const m = members.find((x) => x.id === uid || x.uid === uid);
    return (m?.displayName || "").trim() || r.familyMember;
  };
  const firstName = (uid) => name(uid).split(" ")[0];
  return { me: user?.uid, name, firstName };
}

/** Testo dell'esito di una risposta (null per «Non posso»). */
export function outcomeMessage(r, outcome) {
  switch (outcome.kind) {
    case "claimedByMe":
      return r.outcomeMine;
    case "claimedBy":
      return outcome.name ? r.outcomeTakenBy(outcome.name) : r.outcomeSomeoneFirst;
    case "declined":
      return null;
    default:
      return r.outcomeClosed;
  }
}

/** Testo da condividere con chi è fuori dall'app. */
export function requestShareText(r, locale, { title, dueAt, link }) {
  const what = dueAt ? `${title} · ${requestWhen(dueAt, true, locale)}` : title;
  return r.shareText(what, link);
}

/**
 * Condivide con il foglio di sistema dove c'è (telefono), altrimenti copia.
 * @return {Promise<"shared"|"copied"|"failed">}
 */
async function shareOrCopy(text) {
  if (navigator.share) {
    try {
      await navigator.share({ text });
      return "shared";
    } catch (err) {
      if (err?.name === "AbortError") return "shared";
    }
  }
  try {
    await navigator.clipboard.writeText(text);
    return "copied";
  } catch {
    return "failed";
  }
}

// ── Home ─────────────────────────────────────────────────────────────────────

/**
 * Richieste aperte della famiglia, sopra la dashboard. Senza richieste non
 * disegna niente. `openRequestId` arriva dalla push web (`/?richiesta=…`).
 */
export function RequestsHomeSection({ familyId, openRequestId, onOpenHandled }) {
  const { t, locale } = useTranslation();
  const r = t.requests;
  const names = useNames(familyId);
  const [requests, setRequests] = useState([]);
  const [opened, setOpened] = useState(null);
  const [busyId, setBusyId] = useState(null);
  const [notice, setNotice] = useState(null);

  useEffect(() => {
    if (!familyId) return undefined;
    return listenOpenRequests(familyId, setRequests);
  }, [familyId]);

  useEffect(() => {
    if (!openRequestId) return;
    setOpened(openRequestId);
    onOpenHandled?.();
  }, [openRequestId, onOpenHandled]);

  useEffect(() => {
    if (!notice) return undefined;
    const id = setTimeout(() => setNotice(null), 3500);
    return () => clearTimeout(id);
  }, [notice]);

  const answer = async (req, yes) => {
    setBusyId(req.id);
    try {
      const outcome = await respondToRequest({ familyId, requestId: req.id, yes });
      const msg = outcomeMessage(r, outcome);
      if (msg) setNotice(msg);
    } catch {
      setNotice(r.respondFailed);
    } finally {
      setBusyId(null);
    }
  };

  return (
    <>
      {notice && <div className="req-notice">{notice}</div>}
      {requests.length > 0 && (
        <div className="req-list">
          {requests.map((req) => {
            const isMine = req.createdBy === names.me;
            const myAnswer = req.responses.find((x) => x.key === names.me);
            const no = req.responses.filter((x) => !x.isYes && x.name).map((x) => x.name);
            return (
              <section key={req.id} className="req-card">
                <button className="req-card-main" onClick={() => setOpened(req.id)}>
                  <span className="req-icon">✋</span>
                  <span className="req-text">
                    <span className="req-kicker">
                      {isMine ? r.youAsked : r.asks(names.firstName(req.createdBy))}
                    </span>
                    <span className="req-title">{req.title}</span>
                    {req.dueAt && (
                      <span className="req-when">{requestWhen(req.dueAt, req.dueHasTime, locale)}</span>
                    )}
                    {isMine && (
                      <span className="req-sub">{no.length ? r.cantList(no.join(", ")) : r.waiting}</span>
                    )}
                  </span>
                  <span className="req-chevron">›</span>
                </button>
                {!isMine && (
                  <div className="req-actions">
                    <button
                      className="req-btn primary"
                      disabled={busyId === req.id}
                      onClick={() => answer(req, true)}
                    >
                      {r.yes}
                    </button>
                    <button
                      className="req-btn"
                      disabled={busyId === req.id || myAnswer?.isYes === false}
                      onClick={() => answer(req, false)}
                    >
                      {myAnswer?.isYes === false ? r.saidNo : r.no}
                    </button>
                  </div>
                )}
              </section>
            );
          })}
        </div>
      )}
      {opened && (
        <FamilyRequestModal familyId={familyId} requestId={opened} onClose={() => setOpened(null)} />
      )}
    </>
  );
}

// ── Dettaglio ────────────────────────────────────────────────────────────────

export function FamilyRequestModal({ familyId, requestId, onClose }) {
  const { t, locale } = useTranslation();
  const r = t.requests;
  const names = useNames(familyId);
  const navigate = useNavigate();
  const [req, setReq] = useState(undefined); // undefined = carico, null = non c'è
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(null);
  const [confirmCancel, setConfirmCancel] = useState(false);

  useEffect(() => listenRequest(familyId, requestId, setReq), [familyId, requestId]);

  const isMine = req && req.createdBy === names.me;
  const myAnswer = req?.responses.find((x) => x.key === names.me);

  const respond = async (yes) => {
    setBusy(true);
    setMessage(null);
    try {
      setMessage(outcomeMessage(r, await respondToRequest({ familyId, requestId, yes })));
    } catch {
      setMessage(r.respondFailed);
    } finally {
      setBusy(false);
    }
  };

  const withdraw = async () => {
    setBusy(true);
    setConfirmCancel(false);
    try {
      await cancelRequest({ familyId, requestId });
    } catch {
      setMessage(r.cancelFailed);
    } finally {
      setBusy(false);
    }
  };

  const resend = async () => {
    const link = savedShareLink(requestId);
    if (!link || !req) return;
    const res = await shareOrCopy(requestShareText(r, locale, { title: req.title, dueAt: req.dueAt, link }));
    if (res === "copied") setMessage(r.copied);
  };

  const statusLine = () => {
    if (!req) return null;
    if (req.status === "claimed") {
      let text;
      if (req.claimedByUid && req.claimedByUid === names.me) text = r.claimedYou;
      else if (req.claimedByExternal) text = r.claimedByLink(req.claimedByName || "");
      else text = r.claimedBy(req.claimedByUid ? names.name(req.claimedByUid) : req.claimedByName || "");
      return <div className="req-status ok">✓ {text}</div>;
    }
    if (req.status === "cancelled") return <div className="req-status">{r.cancelled}</div>;
    if (req.isOpen) return <div className="req-status">{r.waiting}</div>;
    return <div className="req-status">{r.expired}</div>;
  };

  return (
    <Modal onClose={onClose}>
      <div className="modal-header">
        <button className="modal-icon-btn" onClick={onClose}>
          ✕
        </button>
      </div>
      <div className="modal-title">{r.title}</div>
      {req === undefined && <p className="modal-hint">…</p>}
      {req === null && (
        <>
          <p>
            <strong>{r.unavailable}</strong>
          </p>
          <p className="modal-hint">{r.unavailableHint}</p>
        </>
      )}
      {req && (
        <>
          <div className="modal-section req-detail-head">
            <div className="req-kicker">{isMine ? r.youAsked : r.asks(names.firstName(req.createdBy))}</div>
            <div className="req-detail-title">{req.title}</div>
            {req.dueAt && <div className="req-when">{requestWhen(req.dueAt, req.dueHasTime, locale)}</div>}
            {req.notes && <div className="req-sub">{req.notes}</div>}
          </div>

          <div className="modal-label">{r.replies}</div>
          <div className="modal-section">
            <div className="modal-row">{statusLine()}</div>
            {req.responses
              .filter((x) => !x.isYes)
              .map((x) => (
                <div className="modal-row" key={x.key}>
                  <span>{x.isExternal ? r.fromLink(x.name) : x.key === names.me ? r.you : x.name}</span>
                  <span className="req-muted">{r.cant}</span>
                </div>
              ))}
          </div>

          {message && <p className="modal-hint">{message}</p>}

          {req.isOpen && !isMine && (
            <div className="req-actions">
              <button className="req-btn primary" disabled={busy} onClick={() => respond(true)}>
                {r.yes}
              </button>
              <button
                className="req-btn"
                disabled={busy || myAnswer?.isYes === false}
                onClick={() => respond(false)}
              >
                {r.no}
              </button>
            </div>
          )}
          {req.isOpen && isMine && (
            <div className="req-actions column">
              {req.hasExternalLink && savedShareLink(req.id) && (
                <button className="req-btn" onClick={resend}>
                  {r.resendLink}
                </button>
              )}
              {confirmCancel ? (
                <div className="req-confirm">
                  <p>
                    <strong>{r.withdrawQ}</strong> {r.withdrawHint}
                  </p>
                  <div className="req-actions">
                    <button className="req-btn danger" disabled={busy} onClick={withdraw}>
                      {r.withdrawConfirm}
                    </button>
                    <button className="req-btn" onClick={() => setConfirmCancel(false)}>
                      {r.cancel}
                    </button>
                  </div>
                </div>
              ) : (
                <button className="req-link danger" disabled={busy} onClick={() => setConfirmCancel(true)}>
                  {r.withdraw}
                </button>
              )}
            </div>
          )}
          {req.status === "claimed" && req.todoId && req.listId && (
            <div className="req-actions">
              <button
                className="req-btn"
                onClick={() => {
                  onClose();
                  navigate(`/todo?lista=${encodeURIComponent(req.listId)}`);
                }}
              >
                {r.openTodo}
              </button>
            </div>
          )}
        </>
      )}
    </Modal>
  );
}

// ── Editor del to-do ─────────────────────────────────────────────────────────

/** Riga dell'editor: «Chiedi a qualcuno…» o il riassunto di chi si chiede. */
export function AskRequestRow({ draft, members, onEdit, onClear }) {
  const { t } = useTranslation();
  const r = t.requests;
  if (!draft) {
    return (
      <div className="modal-row clickable req-ask-row" onClick={onEdit}>
        <span>
          <span className="req-ask-label">
            <span className="req-emoji">✋</span>
            {r.askSomeone}
          </span>
          <span className="req-ask-hint">{r.askHint}</span>
        </span>
        <span>›</span>
      </div>
    );
  }
  const parts = draft.recipients
    .map((uid) => members.find((m) => m.id === uid)?.displayName)
    .filter(Boolean);
  if (draft.askOutside) parts.push(draft.outsideLabel.trim() || r.outsideLower);
  return (
    <>
      <div className="modal-row clickable" onClick={onEdit}>
        <span>
          <span className="req-emoji">✋</span>
          {parts.join(", ")}
        </span>
        <span>›</span>
      </div>
      <div className="modal-row">
        <span className="req-ask-hint">{r.todoBornHint}</span>
      </div>
      <div className="modal-row clickable" onClick={onClear}>
        <span className="req-danger-text">{r.dontAsk}</span>
      </div>
    </>
  );
}

/** Vista «Chiedi a…» dentro la modale del to-do. */
export function AskRequestView({ initial, members, availability, onBack, onConfirm }) {
  const { t, locale } = useTranslation();
  const hhmm = (d) => d.toLocaleTimeString(locale, { hour: "2-digit", minute: "2-digit" });
  const r = t.requests;
  const [work, setWork] = useState(() => initial || { ...emptyDraft(), askOutside: members.length === 0 });

  const toggle = (uid) =>
    setWork((w) => ({
      ...w,
      recipients: w.recipients.includes(uid) ? w.recipients.filter((x) => x !== uid) : [...w.recipients, uid],
    }));

  return (
    <Modal onClose={onBack}>
      <div className="modal-header">
        <button className="modal-icon-btn" onClick={onBack}>
          ‹
        </button>
        <button className="modal-save-btn" disabled={draftIsEmpty(work)} onClick={() => onConfirm(work)}>
          ✓
        </button>
      </div>
      <div className="modal-title">{r.askTitle}</div>

      {/* Contesto, non attribuito a nessuno: gli eventi non dicono chi partecipa. */}
      {availability && availability.events.length > 0 && (
        <>
          <div className="modal-label">{r.calendarAround(hhmm(availability.around))}</div>
          <div className="modal-section">
            {availability.events.map((e) => (
              <div key={e.id} className="modal-row">
                <span className="req-muted req-time">
                  {e.isAllDay ? r.allDay : `${hhmm(e.start)}–${hhmm(e.end)}`}
                </span>
                <span className="req-grow">{e.title}</span>
              </div>
            ))}
          </div>
        </>
      )}

      {members.length === 0 ? (
        <p className="modal-hint">{r.onlyYou}</p>
      ) : (
        <>
          <div className="modal-label">{r.inFamily}</div>
          <div className="modal-section">
            {members.map((m) => (
              <div key={m.id} className="modal-row clickable" onClick={() => toggle(m.id)}>
                <span className="req-member">
                  <span>{m.displayName || r.familyMember}</span>
                  {availability?.busy[m.id]?.[0] && (
                    <span className="req-busy">
                      {r.alreadyHas(availability.busy[m.id][0].title, hhmm(availability.busy[m.id][0].start))}
                    </span>
                  )}
                </span>
                <span className={`modal-check ${work.recipients.includes(m.id) ? "on" : "off"}`}>✓</span>
              </div>
            ))}
          </div>
          <p className="modal-hint">{r.inFamilyHint}</p>
        </>
      )}

      <div className="modal-label">{r.withLink}</div>
      <div className="modal-section">
        <div className="modal-row clickable" onClick={() => setWork((w) => ({ ...w, askOutside: !w.askOutside }))}>
          <span>{r.outside}</span>
          <span className={`modal-check ${work.askOutside ? "on" : "off"}`}>✓</span>
        </div>
        {work.askOutside && (
          <>
            <div className="modal-row">
              <input
                className="modal-field req-inline-field"
                placeholder={r.outsideLabel}
                maxLength={40}
                value={work.outsideLabel}
                onChange={(e) => setWork((w) => ({ ...w, outsideLabel: e.target.value }))}
              />
            </div>
            <div
              className="modal-row clickable"
              onClick={() => setWork((w) => ({ ...w, includeInvite: !w.includeInvite }))}
            >
              <span>{r.includeInvite}</span>
              <span className={`modal-check ${work.includeInvite ? "on" : "off"}`}>✓</span>
            </div>
          </>
        )}
      </div>
      <p className="modal-hint">
        {!work.askOutside ? r.outsideHint : work.includeInvite ? r.withLinkHintInvite : r.withLinkHint}
      </p>
    </Modal>
  );
}

/** Vista «Richiesta inviata» con il link per chi è fuori dall'app. */
export function RequestSentView({ created, title, dueAt, onDone }) {
  const { t, locale } = useTranslation();
  const r = t.requests;
  const [copied, setCopied] = useState(false);
  const text = created.shareLink
    ? requestShareText(r, locale, { title, dueAt, link: created.shareLink })
    : null;

  const share = async () => {
    if (!text) return;
    if ((await shareOrCopy(text)) === "copied") setCopied(true);
  };
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(created.shareLink);
      setCopied(true);
    } catch {
      /* niente appunti: resta il bottone di condivisione */
    }
  };

  return (
    <Modal onClose={onDone}>
      <div className="modal-header">
        <span />
        <button className="modal-save-btn" onClick={onDone}>
          {r.done}
        </button>
      </div>
      <div className="req-sent">
        <div className="req-sent-icon">✋</div>
        <div className="modal-title">{r.sentTitle}</div>
        <p>{created.notifiedCount > 0 ? r.sentNotified : r.sentLinkOnly}</p>
        {text && (
          <div className="req-actions column">
            <button className="req-btn primary" onClick={share}>
              {r.sendLink}
            </button>
            <button className="req-btn" onClick={copy}>
              {copied ? `✓ ${r.copied}` : r.copyLink}
            </button>
          </div>
        )}
        <p className="modal-hint">{r.todoBornHint}</p>
      </div>
    </Modal>
  );
}
