/**
 * Una bolla della chat. Porta sul web `ChatBubble` (iOS): tutti i tipi di
 * messaggio, la citazione, le reazioni, le spunte di lettura e il menu che si
 * apre sul messaggio.
 *
 * Il menu qui è un pulsante che compare al passaggio del mouse invece del
 * long-press del telefono: le voci restano le stesse, ma su un desktop un
 * gesto tenuto premuto non lo cerca nessuno.
 */
import { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { REACTION_EMOJIS } from "../services/chat";
import ChatAudioPlayer from "./ChatAudioPlayer";
import { formatBytes, formatDuration } from "./chatFormat";

export { formatBytes, formatDuration };


const timeOf = (date, locale) =>
  date ? date.toLocaleTimeString(locale === "en" ? "en-US" : "it-IT", { hour: "2-digit", minute: "2-digit" }) : "";

/** URL nel testo: cliccabili, con il dominio in chiaro sotto. */
const URL_RE = /(https?:\/\/[^\s]+)/g;

function TextWithLinks({ text, mentions }) {
  const mentionNames = new Set(mentions.map((m) => `@${m.displayName}`));
  const parts = text.split(URL_RE);
  return (
    <>
      {parts.map((part, i) => {
        if (i % 2 === 1) {
          return (
            <a key={i} href={part} target="_blank" rel="noreferrer" className="chat-link">
              {part}
            </a>
          );
        }
        // Le menzioni si evidenziano: sono ciò che fa arrivare la notifica a
        // una persona precisa, e devono vedersi come tali.
        return part.split(/(@[\wÀ-ÿ'’.\- ]+)/g).map((chunk, j) =>
          mentionNames.has(chunk.trimEnd()) || mentionNames.has(chunk) ? (
            <strong key={`${i}-${j}`} className="chat-mention">
              {chunk}
            </strong>
          ) : (
            <span key={`${i}-${j}`}>{chunk}</span>
          )
        );
      })}
    </>
  );
}

function LocationBubble({ latitude, longitude, label }) {
  const bbox = [longitude - 0.004, latitude - 0.003, longitude + 0.004, latitude + 0.003].join(",");
  return (
    <a
      className="chat-location"
      href={`https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}#map=16/${latitude}/${longitude}`}
      target="_blank"
      rel="noreferrer"
    >
      <iframe
        title={label}
        src={`https://www.openstreetmap.org/export/embed.html?bbox=${bbox}&layer=mapnik&marker=${latitude},${longitude}`}
        loading="lazy"
      />
      <span>📍 {latitude.toFixed(5)}, {longitude.toFixed(5)}</span>
    </a>
  );
}

function ContactBubble({ contact, labels }) {
  const name = `${contact.givenName || ""} ${contact.familyName || ""}`.trim() || labels.contact;
  return (
    <div className="chat-contact">
      <strong>👤 {name}</strong>
      {(contact.phoneNumbers || []).map((p, i) => (
        <a key={`p${i}`} href={`tel:${p.value}`}>
          {p.label ? `${p.label}: ` : ""}
          {p.value}
        </a>
      ))}
      {(contact.emailAddresses || []).map((e, i) => (
        <a key={`e${i}`} href={`mailto:${e.value}`}>
          {e.label ? `${e.label}: ` : ""}
          {e.value}
        </a>
      ))}
    </div>
  );
}

export default function ChatBubble({
  message,
  isMine,
  locale,
  labels,
  repliedTo,
  memberCount,
  onReply,
  onEdit,
  onDelete,
  onDeleteForMe,
  onReact,
  onSave,
  onOpenMedia,
  onJumpTo,
  highlighted,
}) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [pickerOpen, setPickerOpen] = useState(false);
  /** Posizione a schermo del pannello aperto, in coordinate di viewport. */
  const [anchor, setAnchor] = useState(null);
  const wrapRef = useRef(null);
  const menuBtnRef = useRef(null);
  const panelRef = useRef(null);

  /**
   * Il menu esce dalla bolla ed è più largo di lei, ma la lista dei messaggi
   * scorre (`overflow-y: auto`) e ritaglia tutto ciò che sborda: in posizione
   * assoluta il pannello veniva tagliato a metà. Si disegna quindi in un
   * portale su `body`, ancorato al pulsante con coordinate di viewport, e si
   * ribalta verso l'alto o verso sinistra quando lo schermo finisce.
   */
  const openPanel = useCallback((which) => {
    const rect = menuBtnRef.current?.getBoundingClientRect();
    if (!rect) return;
    const width = which === "menu" ? 200 : 230;
    const height = which === "menu" ? 250 : 46;
    setAnchor({
      left: Math.max(8, Math.min(rect.right - width, window.innerWidth - width - 8)),
      top:
        rect.bottom + height > window.innerHeight - 8
          ? Math.max(8, rect.top - height - 4)
          : rect.bottom + 4,
    });
    setMenuOpen(which === "menu");
    setPickerOpen(which === "picker");
  }, []);

  useEffect(() => {
    if (!menuOpen && !pickerOpen) return undefined;
    const close = (e) => {
      if (!wrapRef.current?.contains(e.target) && !panelRef.current?.contains(e.target)) {
        setMenuOpen(false);
        setPickerOpen(false);
      }
    };
    const dismiss = () => {
      setMenuOpen(false);
      setPickerOpen(false);
    };
    document.addEventListener("mousedown", close);
    // Scorrendo, un pannello ancorato a coordinate fisse resterebbe fermo
    // mentre la bolla scivola via: meglio chiuderlo.
    window.addEventListener("scroll", dismiss, true);
    window.addEventListener("resize", dismiss);
    return () => {
      document.removeEventListener("mousedown", close);
      window.removeEventListener("scroll", dismiss, true);
      window.removeEventListener("resize", dismiss);
    };
  }, [menuOpen, pickerOpen]);

  const canEdit = isMine && message.type === "text";
  const hasMedia = ["photo", "video", "audio", "document", "mediaGroup"].includes(message.type);

  // Letto da tutti gli altri membri: è la seconda spunta, e vale solo sui
  // messaggi miei — sugli altrui non direbbe niente di utile.
  const readByOthers = message.readBy.filter((id) => id !== message.senderId).length;
  const allRead = memberCount > 1 && readByOthers >= memberCount - 1;

  if (message.isDeleted) {
    return (
      <div className={`chat-row${isMine ? " mine" : ""}`}>
        <div className="chat-bubble deleted">
          <em>{labels.deletedMessage}</em>
        </div>
      </div>
    );
  }

  const mediaBox = mediaBoxSize(message.mediaWidth, message.mediaHeight);

  const body = () => {
    switch (message.type) {
      case "photo":
        return (
          <img
            className={mediaBox ? "chat-media sized" : "chat-media"}
            style={mediaBox || undefined}
            src={message.mediaURL}
            alt=""
            onClick={() => onOpenMedia({ url: message.mediaURL, type: "photo", message, index: 0 })}
          />
        );
      case "video":
        return (
          <video
            className={mediaBox ? "chat-media sized" : "chat-media"}
            style={mediaBox || undefined}
            src={message.mediaURL}
            controls
            preload="metadata"
          />
        );
      case "audio":
        return <ChatAudioPlayer url={message.mediaURL} duration={message.mediaDurationSeconds} />;
      case "document":
        return (
          <a className="chat-document" href={message.mediaURL} target="_blank" rel="noreferrer">
            📄
            <span>
              <strong>{message.text || labels.document}</strong>
              <small>{formatBytes(message.mediaFileSize)}</small>
            </span>
          </a>
        );
      case "mediaGroup":
        return (
          <div className={`chat-group items-${Math.min(message.mediaGroupURLs.length, 4)}`}>
            {message.mediaGroupURLs.map((url, i) =>
              message.mediaGroupTypes[i] === "video" ? (
                <video key={url} src={url} controls preload="metadata" />
              ) : (
                <img
                  key={url}
                  src={url}
                  alt=""
                  onClick={() => onOpenMedia({ url, type: "photo", message, index: i })}
                />
              )
            )}
          </div>
        );
      case "location":
        return (
          <LocationBubble
            latitude={message.latitude}
            longitude={message.longitude}
            label={labels.location}
          />
        );
      case "contact":
        return <ContactBubble contact={message.contact || {}} labels={labels} />;
      default:
        return (
          <p className="chat-text">
            <TextWithLinks text={message.text} mentions={message.mentions} />
          </p>
        );
    }
  };

  return (
    <div
      className={`chat-row${isMine ? " mine" : ""}${highlighted ? " highlighted" : ""}`}
      id={`msg-${message.id}`}
      ref={wrapRef}
    >
      <div className="chat-bubble">
        {!isMine && <span className="chat-sender">{message.senderName}</span>}

        {repliedTo && (
          <button className="chat-reply-quote" onClick={() => onJumpTo(repliedTo.id)}>
            <strong>{repliedTo.senderName}</strong>
            <span>{repliedTo.preview}</span>
          </button>
        )}

        {body()}

        <div className="chat-meta">
          {message.editedAt && <span>{labels.edited}</span>}
          <span>{timeOf(message.createdAt, locale)}</span>
          {isMine && <span className="chat-ticks">{allRead ? "✓✓" : "✓"}</span>}
        </div>

        {Object.keys(message.reactions).length > 0 && (
          <div className="chat-reactions">
            {Object.entries(message.reactions).map(([emoji, uids]) => (
              <button key={emoji} onClick={() => onReact(emoji)}>
                {emoji} {uids.length}
              </button>
            ))}
          </div>
        )}

        <button
          ref={menuBtnRef}
          className="chat-menu-btn"
          onClick={() => (menuOpen ? setMenuOpen(false) : openPanel("menu"))}
          title={labels.actions}
        >
          ⋯
        </button>

        {menuOpen && anchor && createPortal(
          <div className="chat-menu floating" ref={panelRef} style={{ top: anchor.top, left: anchor.left }}>
            <button onClick={() => { setMenuOpen(false); onReply(); }}>↩︎ {labels.reply}</button>
            <button onClick={() => openPanel("picker")}>🙂 {labels.react}</button>
            {message.type === "text" && (
              <button
                onClick={() => {
                  navigator.clipboard.writeText(message.text);
                  setMenuOpen(false);
                }}
              >
                📋 {labels.copy}
              </button>
            )}
            {(message.type === "text" || hasMedia) && (
              <button onClick={() => { setMenuOpen(false); onSave(); }}>💾 {labels.saveTo}</button>
            )}
            {canEdit && (
              <button onClick={() => { setMenuOpen(false); onEdit(); }}>✏️ {labels.edit}</button>
            )}
            <button className="danger" onClick={() => { setMenuOpen(false); onDeleteForMe(); }}>
              🙈 {labels.deleteForMe}
            </button>
            {isMine && (
              <button className="danger" onClick={() => { setMenuOpen(false); onDelete(); }}>
                🗑 {labels.deleteForEveryone}
              </button>
            )}
          </div>,
          document.body
        )}

        {pickerOpen && anchor && createPortal(
          <div
            className="chat-reaction-picker floating"
            ref={panelRef}
            style={{ top: anchor.top, left: anchor.left }}
          >
            {REACTION_EMOJIS.map((emoji) => (
              <button key={emoji} onClick={() => { setPickerOpen(false); onReact(emoji); }}>
                {emoji}
              </button>
            ))}
          </div>,
          document.body
        )}
      </div>
    </div>
  );
}

/**
 * Riquadro di foto/video come WhatsApp, iOS e Android: gli orizzontali prendono
 * tutta la larghezza, i verticali crescono fino a un tetto e poi si restringono.
 * Senza dimensioni (messaggi vecchi) null: il browser usa le proporzioni vere
 * appena l'immagine arriva.
 */
export function mediaBoxSize(width, height) {
  if (!(width > 0 && height > 0)) return null;
  const maxW = 270;
  const maxH = maxW * 1.2;
  const aspect = height / width;
  let w = maxW;
  let h = maxW * aspect;
  if (h > maxH) {
    h = maxH;
    w = Math.max(maxH / aspect, maxW * 0.55);
  }
  h = Math.max(h, maxW * 0.45);
  return { width: Math.round(w), height: Math.round(h) };
}

/**
 * Anello d'invio con lo stop al centro, come WhatsApp, iOS e Android: gira
 * finché non arriva il primo progresso, poi si riempie. Il tocco annulla.
 */
export function UploadRing({ progress, onCancel, label, size = 46, variant = "media" }) {
  const stroke = Math.max(2.5, size * 0.075);
  const r = size / 2 - stroke * 2;
  const circumference = 2 * Math.PI * r;
  const determinate = typeof progress === "number";
  const filled = determinate ? Math.max(progress, 0.03) : 0.25;
  return (
    <button
      type="button"
      className={`chat-upload-ring ${variant}${determinate ? "" : " spinning"}`}
      style={{ width: size, height: size }}
      onClick={onCancel}
      aria-label={label}
      title={label}
    >
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
        <circle className="track" cx={size / 2} cy={size / 2} r={r} strokeWidth={stroke} fill="none" />
        <circle
          className="arc"
          cx={size / 2}
          cy={size / 2}
          r={r}
          strokeWidth={stroke}
          fill="none"
          strokeLinecap="round"
          strokeDasharray={`${circumference * filled} ${circumference}`}
          transform={`rotate(-90 ${size / 2} ${size / 2})`}
        />
      </svg>
      <span className="stop" style={{ width: size * 0.2, height: size * 0.2 }} />
    </button>
  );
}

/**
 * Bolla locale di un invio in corso. Sul web non c'è un database locale: finché
 * il messaggio vero non arriva da Firestore si mostra questa, con l'anteprima
 * del file, l'anello e lo stop.
 */
export function ChatUploadBubble({ upload, locale, labels, onCancel }) {
  const isVisual = upload.type === "photo" || upload.type === "video" || upload.type === "mediaGroup";
  const box = mediaBoxSize(upload.width, upload.height) || { width: 270, height: 202 };
  return (
    <div className="chat-row mine">
      <div className="chat-bubble">
        {isVisual ? (
          <div className="chat-upload-media" style={box}>
            {upload.previewURL &&
              (upload.previewType === "video" ? (
                <video src={upload.previewURL} muted playsInline preload="metadata" />
              ) : (
                <img src={upload.previewURL} alt="" />
              ))}
            <UploadRing progress={upload.progress} onCancel={onCancel} label={labels.cancelUpload} />
          </div>
        ) : (
          <div className="chat-upload-file">
            <UploadRing
              progress={upload.progress}
              onCancel={onCancel}
              label={labels.cancelUpload}
              size={36}
              variant="inline"
            />
            <span>{upload.fileName || labels.uploading}</span>
          </div>
        )}
        <div className="chat-meta">
          <span>{timeOf(upload.createdAt, locale)}</span>
          <span className="chat-ticks">🕓</span>
        </div>
      </div>
    </div>
  );
}
