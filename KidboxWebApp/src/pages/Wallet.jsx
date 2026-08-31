import { useEffect, useMemo, useRef, useState } from "react";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { MissingFamilyKeyError } from "../services/familyKey";
import {
  deleteCard,
  deleteTicket,
  deleteTicketPdf,
  fetchTicketPdf,
  kindInfo,
  listenWallet,
  saveCard,
  saveTicket,
  uploadCardPhoto,
  uploadTicketPdf,
} from "../services/wallet";
import {
  effectiveExpiry,
  kindInfo as docKindInfo,
  listenWalletDocuments,
} from "../services/walletDocuments";
import { fetchDocumentBlob } from "../services/documents";
import Barcode from "../components/Barcode";
import WalletTicketModal from "../components/WalletTicketModal";
import WalletCardModal from "../components/WalletCardModal";
import "./Wallet.css";

export default function Wallet() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();
  const w = t.wallet;
  const members = useFamilyMembers(currentFamilyId);
  const pdfInputRef = useRef(null);

  const [tab, setTab] = useState("tickets");
  const [tickets, setTickets] = useState([]);
  const [cards, setCards] = useState([]);
  const [walletDocs, setWalletDocs] = useState([]);
  const [keyMissing, setKeyMissing] = useState(false);
  const [error, setError] = useState(null);
  const [search, setSearch] = useState("");

  const [editingTicket, setEditingTicket] = useState(null);
  const [editingCard, setEditingCard] = useState(null);
  const [detail, setDetail] = useState(null); // { type: "ticket"|"card", id }
  const [toast, setToast] = useState(null);

  useEffect(() => {
    if (!currentFamilyId || !user) return undefined;
    setKeyMissing(false);
    return listenWallet({
      familyId: currentFamilyId,
      userId: user.uid,
      onChange: ({ tickets: tk, cards: cd }) => {
        setTickets(tk);
        setCards(cd);
      },
      onError: (err) => {
        if (err instanceof MissingFamilyKeyError) setKeyMissing(true);
        else setError(err.message);
      },
    });
  }, [currentFamilyId, user]);

  // La terza scheda non ha una collezione propria: i documenti del Wallet sono
  // normali documenti di famiglia con i metadati dentro `notes`. Si leggono da
  // dove sono già sincronizzati, senza crearne di nuovi.
  useEffect(() => {
    if (!currentFamilyId || !user) return undefined;
    return listenWalletDocuments({
      familyId: currentFamilyId,
      userId: user.uid,
      onChange: setWalletDocs,
      onError: (err) => setError(err.message),
    });
  }, [currentFamilyId, user]);

  const showToast = (text) => {
    setToast(text);
    window.setTimeout(() => setToast(null), 1800);
  };

  const userName = user?.displayName || "";
  const now = Date.now();

  const q = search.trim().toLowerCase();
  const matches = (values) =>
    !q || values.filter(Boolean).some((v) => String(v).toLowerCase().includes(q));

  // I biglietti si dividono come su iOS: prima quelli che devono ancora
  // succedere, in ordine crescente, poi gli altri dal più recente.
  const { upcoming, past } = useMemo(() => {
    const visible = tickets.filter((tk) =>
      matches([tk.title, tk.emitter, tk.location, tk.arrivalLocation, tk.bookingCode, tk.notes])
    );
    const up = visible
      .filter((tk) => (tk.eventEndDate || tk.eventDate || 0) >= now)
      .sort((a, b) => (a.eventDate || 0) - (b.eventDate || 0));
    const old = visible
      .filter((tk) => !((tk.eventEndDate || tk.eventDate || 0) >= now))
      .sort((a, b) => (b.eventDate || b.updatedAt || 0) - (a.eventDate || a.updatedAt || 0));
    return { upcoming: up, past: old };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tickets, q, now]);

  const visibleCards = useMemo(
    () => cards.filter((c) => matches([c.brandName, c.cardNumber, c.note])),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [cards, q]
  );

  const visibleDocs = useMemo(
    () => walletDocs.filter((d) => matches([d.title, d.meta.holderName, d.meta.documentNumber, d.meta.codiceFiscale])),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [walletDocs, q]
  );

  const openDoc = walletDocs.find((x) => detail?.type === "doc" && x.id === detail.id) || null;
  const openTicket = tickets.find((x) => detail?.type === "ticket" && x.id === detail.id) || null;
  const openCard = cards.find((x) => detail?.type === "card" && x.id === detail.id) || null;

  const fmt = (millis) =>
    millis
      ? new Date(millis).toLocaleString(locale === "en" ? "en-US" : "it-IT", {
          weekday: "short",
          day: "2-digit",
          month: "short",
          hour: "2-digit",
          minute: "2-digit",
        })
      : null;

  const copy = async (value, label) => {
    await navigator.clipboard.writeText(value);
    showToast(`${label}: ${w.copied}`);
  };

  const removeTicket = async (id) => {
    if (!window.confirm(w.confirmDelete)) return;
    await deleteTicket({ familyId: currentFamilyId, userId: user.uid, id });
    await deleteTicketPdf({ familyId: currentFamilyId, ticketId: id });
    setDetail(null);
  };

  const removeCard = async (id) => {
    if (!window.confirm(w.confirmDelete)) return;
    await deleteCard({ familyId: currentFamilyId, userId: user.uid, id });
    setDetail(null);
  };

  const attachPdf = async (file) => {
    if (!file || !openTicket) return;
    try {
      const { url, bytes, fileName } = await uploadTicketPdf({
        familyId: currentFamilyId,
        userId: user.uid,
        ticketId: openTicket.id,
        file,
      });
      await saveTicket({
        familyId: currentFamilyId,
        userId: user.uid,
        userName,
        ticket: { ...openTicket, pdfStorageURL: url, pdfStorageBytes: bytes, pdfFileName: fileName },
      });
    } catch (err) {
      setError(err.message);
    }
  };

  const openDocumentFile = async (walletDoc) => {
    try {
      const blob = await fetchDocumentBlob({
        familyId: currentFamilyId,
        userId: user.uid,
        document: walletDoc,
      });
      window.open(URL.createObjectURL(blob), "_blank", "noopener");
    } catch (err) {
      setError(err.message);
    }
  };

  const openPdf = async (ticket) => {
    try {
      const blob = await fetchTicketPdf({ familyId: currentFamilyId, userId: user.uid, ticket });
      if (!blob) return;
      window.open(URL.createObjectURL(blob), "_blank", "noopener");
    } catch (err) {
      setError(err.message);
    }
  };

  if (keyMissing) {
    return (
      <div className="wl-page">
        <h1>{w.title}</h1>
        <p className="pw-locked">🔒 {w.keyMissing}</p>
      </div>
    );
  }

  return (
    <div className="wl-page">
      <header className="pw-header">
        <h1>{w.title}</h1>
        <div className="pw-toolbar">
          <input
            className="pw-search"
            type="search"
            placeholder={w.search}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <button
            className="pw-btn-primary"
            onClick={() => (tab === "tickets" ? setEditingTicket({}) : setEditingCard({}))}
            disabled={tab === "documents"}
            title={tab === "documents" ? w.readOnlyDocs : undefined}
          >
            + {tab === "cards" ? w.addCard : w.addTicket}
          </button>
        </div>
      </header>

      <div className="pw-chips">
        <button
          className={"pw-chip" + (tab === "tickets" ? " selected" : "")}
          onClick={() => setTab("tickets")}
        >
          🎫 {w.tabTickets}
        </button>
        <button
          className={"pw-chip" + (tab === "documents" ? " selected" : "")}
          onClick={() => setTab("documents")}
        >
          🪪 {w.tabDocuments}
        </button>
        <button
          className={"pw-chip" + (tab === "cards" ? " selected" : "")}
          onClick={() => setTab("cards")}
        >
          💳 {w.tabCards}
        </button>
      </div>

      {error && <p className="error">{error}</p>}

      {tab === "tickets" ? (
        upcoming.length === 0 && past.length === 0 ? (
          <p className="pw-empty">{w.noTickets}</p>
        ) : (
          <>
            {upcoming.length > 0 && (
              <TicketGroup title={w.upcoming} tickets={upcoming} fmt={fmt} locale={locale} onOpen={(id) => setDetail({ type: "ticket", id })} />
            )}
            {past.length > 0 && (
              <TicketGroup title={w.past} tickets={past} fmt={fmt} locale={locale} muted onOpen={(id) => setDetail({ type: "ticket", id })} />
            )}
          </>
        )
      ) : tab === "documents" ? (
        visibleDocs.length === 0 ? (
          <p className="pw-empty">{w.noWalletDocs}</p>
        ) : (
          <>
            <p className="pw-hint">{w.readOnlyDocs}</p>
            <div className="wl-docs">
              {visibleDocs.map((d) => {
                const info = docKindInfo(d.meta.kind);
                const expiry = effectiveExpiry(d.meta);
                const state = expiryState(expiry);
                return (
                  <button
                    key={d.id}
                    className="wl-doc"
                    onClick={() => setDetail({ type: "doc", id: d.id })}
                  >
                    <span className="wl-doc-top" style={{ background: info.color }}>
                      <span className="wl-doc-emoji">{info.emoji}</span>
                      <span className="wl-doc-kind">{locale === "en" ? info.en : info.it}</span>
                    </span>
                    <span className="wl-doc-body">
                      <span className="wl-doc-holder">
                        {d.meta.holderName || d.title || "—"}
                      </span>
                      {d.meta.documentNumber && (
                        <span className="wl-doc-number">{d.meta.documentNumber}</span>
                      )}
                      {expiry && (
                        <span className={"wl-doc-expiry" + (state ? " " + state : "")}>
                          {state === "expired" ? w.expiredDoc : w.expiryDate}: {fmtDay(expiry, locale)}
                        </span>
                      )}
                    </span>
                  </button>
                );
              })}
            </div>
          </>
        )
      ) : visibleCards.length === 0 ? (
        <p className="pw-empty">{w.noCards}</p>
      ) : (
        <div className="wl-cards">
          {visibleCards.map((c) => (
            <button
              key={c.id}
              className="wl-card"
              style={{
                background: `linear-gradient(135deg, ${c.primaryColorHex}, ${c.secondaryColorHex})`,
              }}
              onClick={() => setDetail({ type: "card", id: c.id })}
            >
              <span className="wl-card-brand">{c.brandName}</span>
              {c.cardNumber && <span className="wl-card-number">{c.cardNumber}</span>}
            </button>
          ))}
        </div>
      )}

      {/* ── Dettaglio biglietto ── */}
      {openTicket && (
        <div className="pw-detail-overlay" onClick={() => setDetail(null)}>
          <aside className="pw-detail" onClick={(e) => e.stopPropagation()}>
            <header>
              <h2>
                {kindInfo(openTicket.kind).emoji} {openTicket.title}
              </h2>
              <button onClick={() => setDetail(null)}>✕</button>
            </header>

            {openTicket.barcodeText && (
              <Barcode text={openTicket.barcodeText} format={openTicket.barcodeFormat} />
            )}

            <Field label={w.kind} value={locale === "en" ? kindInfo(openTicket.kind).en : kindInfo(openTicket.kind).it} />
            <Field label={w.emitter} value={openTicket.emitter} />
            <Field label={w.eventDate} value={fmt(openTicket.eventDate)} />
            <Field label={w.eventEndDate} value={fmt(openTicket.eventEndDate)} />
            <Field label={w.location} value={openTicket.location} />
            <Field label={w.arrival} value={openTicket.arrivalLocation} />
            <Field label={w.seat} value={openTicket.seat} />
            <Field
              label={w.bookingCode}
              value={openTicket.bookingCode}
              onCopy={() => copy(openTicket.bookingCode, w.bookingCode)}
              copyLabel={w.copy}
            />
            <Field label={w.holder} value={openTicket.holderName} />
            <Field label={w.notes} value={openTicket.notes} />

            <div className="pw-detail-row">
              <span className="pw-detail-label">{w.pdf}</span>
              <span className="pw-detail-value">{openTicket.pdfFileName || "—"}</span>
              {openTicket.pdfStorageURL ? (
                <button onClick={() => openPdf(openTicket)}>{w.openPdf}</button>
              ) : (
                <button onClick={() => pdfInputRef.current?.click()}>{w.uploadPdf}</button>
              )}
            </div>

            <div className="pw-form-actions">
              <button className="pw-danger" onClick={() => removeTicket(openTicket.id)}>
                {w.delete}
              </button>
              <button
                className="pw-btn-primary"
                onClick={() => {
                  setEditingTicket(openTicket);
                  setDetail(null);
                }}
              >
                {w.edit}
              </button>
            </div>
          </aside>
        </div>
      )}

      {/* ── Dettaglio documento del Wallet ── */}
      {openDoc && (
        <div className="pw-detail-overlay" onClick={() => setDetail(null)}>
          <aside className="pw-detail" onClick={(e) => e.stopPropagation()}>
            <header>
              <h2>
                {docKindInfo(openDoc.meta.kind).emoji}{" "}
                {locale === "en"
                  ? docKindInfo(openDoc.meta.kind).en
                  : docKindInfo(openDoc.meta.kind).it}
              </h2>
              <button onClick={() => setDetail(null)}>✕</button>
            </header>

            <Field label={w.fieldTitle} value={openDoc.title} />
            <Field label={w.holderName} value={openDoc.meta.holderName} />
            <Field
              label={w.codiceFiscale}
              value={openDoc.meta.codiceFiscale}
              onCopy={() => copy(openDoc.meta.codiceFiscale, w.codiceFiscale)}
              copyLabel={w.copy}
            />
            <Field
              label={w.documentNumber}
              value={openDoc.meta.documentNumber}
              onCopy={() => copy(openDoc.meta.documentNumber, w.documentNumber)}
              copyLabel={w.copy}
            />
            <Field label={w.birthInfo} value={openDoc.meta.birthInfo} />
            <Field label={w.issueDate} value={fmtDay(openDoc.meta.issueDate, locale)} />
            <Field label={w.expiryDate} value={fmtDay(openDoc.meta.expiryDate, locale)} />

            {openDoc.meta.patenteCategories.length > 0 && (
              <div className="pw-detail-row">
                <span className="pw-detail-label">{w.categories}</span>
                <span className="pw-detail-value">
                  <ul className="wl-cats">
                    {openDoc.meta.patenteCategories.map((c) => (
                      <li key={c.code}>
                        <strong>{c.code}</strong>
                        <span>
                          {[fmtDay(c.issueDate, locale), fmtDay(c.expiryDate, locale)]
                            .filter(Boolean)
                            .join(" → ")}
                        </span>
                      </li>
                    ))}
                  </ul>
                </span>
              </div>
            )}

            <div className="pw-form-actions">
              <button className="pw-btn-primary" onClick={() => openDocumentFile(openDoc)}>
                {w.openFile}
              </button>
            </div>
          </aside>
        </div>
      )}

      {/* ── Dettaglio tessera ── */}
      {openCard && (
        <div className="pw-detail-overlay" onClick={() => setDetail(null)}>
          <aside className="pw-detail" onClick={(e) => e.stopPropagation()}>
            <header>
              <h2>{openCard.brandName}</h2>
              <button onClick={() => setDetail(null)}>✕</button>
            </header>

            {openCard.cardNumber && (
              <Barcode text={openCard.cardNumber} format={openCard.barcodeFormat} />
            )}

            <Field
              label={w.cardNumber}
              value={openCard.cardNumber}
              onCopy={() => copy(openCard.cardNumber, w.cardNumber)}
              copyLabel={w.copy}
            />
            <Field label={w.notes} value={openCard.note} />

            <div className="wl-photos">
              {openCard.frontPhotoStorageURL && (
                <img src={openCard.frontPhotoStorageURL} alt={w.frontPhoto} />
              )}
              {openCard.backPhotoStorageURL && (
                <img src={openCard.backPhotoStorageURL} alt={w.backPhoto} />
              )}
            </div>

            <div className="pw-form-actions">
              <button className="pw-danger" onClick={() => removeCard(openCard.id)}>
                {w.delete}
              </button>
              <button
                className="pw-btn-primary"
                onClick={() => {
                  setEditingCard(openCard);
                  setDetail(null);
                }}
              >
                {w.edit}
              </button>
            </div>
          </aside>
        </div>
      )}

      <input
        ref={pdfInputRef}
        type="file"
        accept="application/pdf"
        hidden
        onChange={(e) => {
          const f = e.target.files?.[0];
          e.target.value = "";
          if (f) attachPdf(f);
        }}
      />

      {editingTicket && (
        <WalletTicketModal
          ticket={editingTicket}
          members={members}
          locale={locale}
          onSave={(ticket) =>
            saveTicket({ familyId: currentFamilyId, userId: user.uid, userName, ticket })
          }
          onClose={() => setEditingTicket(null)}
        />
      )}

      {editingCard && (
        <WalletCardModal
          card={editingCard}
          members={members}
          onSave={(card) =>
            saveCard({ familyId: currentFamilyId, userId: user.uid, userName, card })
          }
          onUploadPhoto={(side, file) =>
            uploadCardPhoto({
              familyId: currentFamilyId,
              cardId: editingCard.id || "nuova",
              side,
              file,
            })
          }
          onClose={() => setEditingCard(null)}
        />
      )}

      {toast && <div className="pw-toast">{toast}</div>}
    </div>
  );
}

/** Le date dei documenti arrivano come `yyyy-MM-dd`, senza orario né fuso. */
function fmtDay(iso, locale) {
  if (!iso) return null;
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y, m - 1, d).toLocaleDateString(locale === "en" ? "en-US" : "it-IT", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

/** Scaduto, in scadenza entro due mesi, o nulla da segnalare. */
function expiryState(iso) {
  if (!iso) return null;
  const [y, m, d] = iso.split("-").map(Number);
  const when = new Date(y, m - 1, d).getTime();
  const now = Date.now();
  if (when < now) return "expired";
  if (when - now < 60 * 24 * 60 * 60 * 1000) return "soon";
  return null;
}

function Field({ label, value, onCopy, copyLabel }) {
  if (!value) return null;
  return (
    <div className="pw-detail-row">
      <span className="pw-detail-label">{label}</span>
      <span className="pw-detail-value">{value}</span>
      {onCopy && <button onClick={onCopy}>{copyLabel}</button>}
    </div>
  );
}

function TicketGroup({ title, tickets, fmt, locale, muted, onOpen }) {
  return (
    <section className="wl-group">
      <div className="pw-section-head" style={{ cursor: "default" }}>
        <span className="pw-section-title">{title}</span>
        <span className="pw-section-count">{tickets.length}</span>
      </div>
      <div className={"wl-tickets" + (muted ? " muted" : "")}>
        {tickets.map((tk) => {
          const info = kindInfo(tk.kind);
          return (
            <button key={tk.id} className="wl-ticket" onClick={() => onOpen(tk.id)}>
              <span className="wl-ticket-stripe" style={{ background: info.color }} />
              <span className="wl-ticket-body">
                <span className="wl-ticket-top">
                  <span className="wl-ticket-emoji">{info.emoji}</span>
                  <span className="wl-ticket-title">{tk.title}</span>
                </span>
                <span className="wl-ticket-meta">
                  {[fmt(tk.eventDate), tk.location, tk.seat].filter(Boolean).join(" · ") ||
                    (locale === "en" ? info.en : info.it)}
                </span>
              </span>
            </button>
          );
        })}
      </div>
    </section>
  );
}
