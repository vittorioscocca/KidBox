/**
 * Chat di famiglia. Porta sul web `ChatView` + `ChatViewModel` (iOS).
 *
 * Differenze volute rispetto al telefono, tutte per il mezzo e non per fretta:
 * il menu del messaggio si apre con un pulsante invece che tenendo premuto, e
 * la registrazione vocale usa `MediaRecorder`, che nel browser produce il
 * formato che il browser sa produrre (m4a su Safari, webm altrove).
 *
 * Quel che resta identico è il contratto con i client nativi: testo cifrato in
 * `textEnc`, media in chiaro sotto `families/{id}/chat/…`, reazioni in
 * `reactionsJSON`, letture in `readBy` via arrayUnion, «sta scrivendo» nella
 * sottocollezione `typing`.
 */
import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { doc, getDoc } from "firebase/firestore";
import { useAuth } from "../AuthContext";
import { useFamily } from "../FamilyContext";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { useTranslation } from "../i18n/LocaleContext";
import { db } from "../firebase";
import { loadFamilyKey } from "../services/familyKey";
import ChatBubble from "../components/ChatBubble";
import ChatMediaGallery from "../components/ChatMediaGallery";
import Modal from "../components/Modal";
import {
  MAX_GROUP_ITEMS,
  clearChat,
  clearTyping,
  deleteForEveryone,
  deleteForMe,
  editMessage,
  fetchOlderMessages,
  listenMessages,
  listenTyping,
  markAsRead,
  removeFromGroup,
  sendContact,
  sendLocation,
  sendMedia,
  sendMediaGroup,
  sendText,
  setTyping,
  toggleReaction,
} from "../services/chat";
import {
  saveAsEvent,
  saveAsGrocery,
  saveAsNote,
  saveAsTodo,
  saveToDocuments,
  saveToPhotos,
} from "../services/chatSave";
import "./Chat.css";

/** Foto ridotta prima dell'invio, come fa `compressPhoto` su iOS. */
async function compressPhoto(file) {
  if (!file.type.startsWith("image/")) return file;
  try {
    const bitmap = await createImageBitmap(file);
    const scale = Math.min(1, 1600 / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(bitmap.width * scale);
    canvas.height = Math.round(bitmap.height * scale);
    const ctx = canvas.getContext("2d");
    ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    bitmap.close();
    const blob = await new Promise((res) => canvas.toBlob(res, "image/jpeg", 0.82));
    return blob || file;
  } catch {
    // Formato che il browser non sa decodificare: si manda l'originale.
    return file;
  }
}

/**
 * Etichetta del separatore di giorno, nello stile di WhatsApp: «Oggi», «Ieri»,
 * poi giorno della settimana abbreviato con data («gio 9 lug»), e l'anno solo
 * quando non è quello corrente.
 *
 * La data per esteso che c'era prima era corretta ma inutile: in una chat si
 * legge di sfuggita mentre si scorre, e «9 luglio 2026» costringe a leggerla
 * tutta per capire una cosa che «Oggi» dice da sola.
 */
function dayLabel(date, locale, labels) {
  if (!date) return "";
  const tag = locale === "en" ? "en-US" : "it-IT";
  const today = new Date();
  const midnight = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const days = Math.round((midnight(today) - midnight(date)) / 86_400_000);

  if (days === 0) return labels.today;
  if (days === 1) return labels.yesterday;

  const parts = date
    .toLocaleDateString(tag, {
      weekday: "short",
      day: "numeric",
      month: "short",
      ...(date.getFullYear() === today.getFullYear() ? {} : { year: "numeric" }),
    })
    // Alcune lingue infilano virgole e punti nell'abbreviazione: qui la riga
    // deve restare corta come nella chat del telefono.
    .replace(/,/g, "")
    .replace(/\./g, "");
  return parts;
}

/** Emoji della tastierina: le stesse che si usano davvero in una chat di famiglia. */
const EMOJI_PALETTE = [
  "😀", "😂", "🥰", "😍", "😉", "😊", "🤗", "🤔",
  "😅", "😭", "😱", "😴", "🙄", "😎", "🤩", "🥳",
  "👍", "👎", "👏", "🙏", "💪", "🤝", "❤️", "🧡",
  "💛", "💚", "💙", "💜", "🔥", "✨", "🎉", "🎂",
  "🍕", "☕️", "🏠", "🚗", "⚽️", "🐶", "🐱", "🌈",
];

const sameDay = (a, b) =>
  a && b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();

export default function Chat() {
  const { user } = useAuth();
  const { currentFamilyId } = useFamily();
  const { t, locale } = useTranslation();
  const c = t.chat;
  const members = useFamilyMembers(currentFamilyId);

  const [familyKey, setFamilyKey] = useState(null);
  const [chatEnabled, setChatEnabled] = useState(true);
  const [messages, setMessages] = useState([]);
  const [oldestDoc, setOldestDoc] = useState(null);
  const [hasMore, setHasMore] = useState(true);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [typingUsers, setTypingUsers] = useState([]);
  const [displayName, setDisplayName] = useState("");

  const [input, setInput] = useState("");
  const [replyTo, setReplyTo] = useState(null);
  const [editing, setEditing] = useState(null);
  const [mentions, setMentions] = useState([]);
  const [mentionQuery, setMentionQuery] = useState(null);

  const [search, setSearch] = useState("");
  const [searchOpen, setSearchOpen] = useState(false);
  const [highlighted, setHighlighted] = useState(null);

  const [progress, setProgress] = useState(null);
  const [error, setError] = useState(null);
  const [notice, setNotice] = useState(null);
  const [busy, setBusy] = useState(false);

  const [galleryOpen, setGalleryOpen] = useState(false);
  const [saveTarget, setSaveTarget] = useState(null);
  const [contactDraft, setContactDraft] = useState(null);
  const [lightbox, setLightbox] = useState(null);

  const [selecting, setSelecting] = useState(false);
  const [selectedIds, setSelectedIds] = useState([]);
  const [atBottom, setAtBottom] = useState(true);
  const [dragOver, setDragOver] = useState(false);
  /** Testo dell'ultimo invio fallito: serve al pulsante «riprova». */
  const [failedText, setFailedText] = useState(null);

  const [headerMenuOpen, setHeaderMenuOpen] = useState(false);
  const [attachOpen, setAttachOpen] = useState(false);
  const [emojiOpen, setEmojiOpen] = useState(false);

  const [recorder, setRecorder] = useState(null);
  const [recordingSeconds, setRecordingSeconds] = useState(0);
  /** Annullamento: sta in una ref perché `onstop` la legge fuori dal render. */
  const recordingCancelled = useRef(false);

  const listRef = useRef(null);
  const bottomRef = useRef(null);
  const mediaInput = useRef(null);
  const cameraInput = useRef(null);
  const attachRef = useRef(null);
  const headerMenuRef = useRef(null);
  const emojiRef = useRef(null);
  const docInput = useRef(null);
  const typingTimer = useRef(null);
  const uid = user?.uid;

  /* ── Caricamenti iniziali ─────────────────────────────────────────────── */

  useEffect(() => {
    if (!currentFamilyId || !uid) return;
    loadFamilyKey({ familyId: currentFamilyId, userId: uid })
      .then(setFamilyKey)
      .catch(() => setError(c.keyMissing));
  }, [currentFamilyId, uid, c.keyMissing]);

  useEffect(() => {
    if (!uid) return;
    getDoc(doc(db, "users", uid))
      .then((snap) => {
        const d = snap.data() || {};
        setChatEnabled(d.appPrefs?.chatEnabled !== false);
        setDisplayName(d.displayName || user?.displayName || user?.email || "Utente");
      })
      .catch(() => setDisplayName(user?.displayName || user?.email || "Utente"));
  }, [uid, user]);

  useEffect(() => {
    if (!currentFamilyId || !familyKey) return undefined;
    return listenMessages({
      familyId: currentFamilyId,
      familyKey,
      onChange: ({ messages: next, oldestDoc: doc0 }) => {
        // La finestra realtime copre solo gli ultimi 50: i messaggi più vecchi
        // già impaginati stanno in testa e non vanno persi a ogni snapshot.
        setMessages((prev) => {
          const ids = new Set(next.map((m) => m.id));
          const older = prev.filter((m) => !ids.has(m.id) && (!doc0 || m.createdAt < next[0]?.createdAt));
          return [...older, ...next];
        });
        setOldestDoc((prev) => prev ?? doc0);
      },
      onError: (err) => setError(err.message),
    });
  }, [currentFamilyId, familyKey]);

  useEffect(() => {
    if (!currentFamilyId || !uid) return undefined;
    return listenTyping({ familyId: currentFamilyId, excludeUid: uid, onChange: setTypingUsers });
  }, [currentFamilyId, uid]);

  // «Sta scrivendo» va spento uscendo dalla pagina, o resta acceso per sempre.
  useEffect(() => {
    if (!currentFamilyId || !uid) return undefined;
    return () => clearTyping({ familyId: currentFamilyId, uid });
  }, [currentFamilyId, uid]);

  // I due pannelli della barra si chiudono cliccando altrove, come farebbe un
  // menu di sistema: restare aperti dopo aver scelto è il difetto tipico dei
  // popover fatti a mano.
  useEffect(() => {
    if (!attachOpen && !emojiOpen && !headerMenuOpen) return undefined;
    const close = (e) => {
      if (attachOpen && !attachRef.current?.contains(e.target)) setAttachOpen(false);
      if (emojiOpen && !emojiRef.current?.contains(e.target)) setEmojiOpen(false);
      if (headerMenuOpen && !headerMenuRef.current?.contains(e.target)) setHeaderMenuOpen(false);
    };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [attachOpen, emojiOpen, headerMenuOpen]);

  /* ── Letture ──────────────────────────────────────────────────────────── */

  useEffect(() => {
    if (!currentFamilyId || !uid || !messages.length) return;
    const unread = messages
      .filter((m) => m.senderId !== uid && !m.isDeleted && !m.readBy.includes(uid))
      .map((m) => m.id);
    if (unread.length) {
      markAsRead({ familyId: currentFamilyId, messageIds: unread, uid }).catch(() => {});
    }
  }, [messages, currentFamilyId, uid]);

  useEffect(() => {
    // Non si trascina in fondo chi sta leggendo indietro: interromperebbe la
    // lettura a ogni messaggio nuovo.
    if (atBottom) bottomRef.current?.scrollIntoView({ block: "end" });
  }, [messages.length, atBottom]);

  /* ── Dati derivati ────────────────────────────────────────────────────── */

  const visible = useMemo(
    () =>
      messages
        .filter((m) => !m.deletedFor.includes(uid))
        .filter((m) => !search.trim() || (m.text || "").toLowerCase().includes(search.toLowerCase())),
    [messages, uid, search]
  );

  const byId = useMemo(() => new Map(messages.map((m) => [m.id, m])), [messages]);

  const previewOf = useCallback(
    (message) => {
      if (!message) return "";
      switch (message.type) {
        case "photo": return `📷 ${c.photo}`;
        case "video": return `🎬 ${c.video}`;
        case "audio": return `🎤 ${c.audio}`;
        case "document": return `📄 ${message.text || c.document}`;
        case "location": return `📍 ${c.location}`;
        case "contact": return `👤 ${message.text || c.contact}`;
        case "mediaGroup": return `🖼 ${message.mediaGroupURLs.length} ${c.mediaGroup}`;
        default: return message.text || "";
      }
    },
    [c]
  );

  const mentionCandidates = useMemo(() => {
    if (mentionQuery === null) return [];
    const q = mentionQuery.toLowerCase();
    return members
      .filter((m) => m.id !== uid)
      .map((m) => ({ uid: m.id, displayName: m.displayName || m.email || "Utente" }))
      .filter((m) => !q || m.displayName.toLowerCase().includes(q))
      .slice(0, 6);
  }, [mentionQuery, members, uid]);

  /* ── Azioni ───────────────────────────────────────────────────────────── */

  /** Esegue l'azione mostrando l'errore invece di lasciarlo cadere. Ritorna
   *  `false` quando è fallita, così chi chiama può reagire. */
  const guard = async (action) => {
    setError(null);
    setBusy(true);
    try {
      await action();
      return true;
    } catch (err) {
      setError(err.message);
      return false;
    } finally {
      setBusy(false);
      setProgress(null);
    }
  };

  /** Come `guard`, ma tiene da parte il testo perché si possa riprovare. */
  const guardText = async (text, action) => {
    if (!(await guard(action))) setFailedText(text);
  };

  const onInputChange = (value) => {
    setInput(value);
    const match = /@([\wÀ-ÿ'’.-]*)$/.exec(value);
    setMentionQuery(match ? match[1] : null);

    if (!currentFamilyId || !uid) return;
    setTyping({ familyId: currentFamilyId, uid, displayName, isTyping: true });
    clearTimeout(typingTimer.current);
    typingTimer.current = setTimeout(
      () => setTyping({ familyId: currentFamilyId, uid, displayName, isTyping: false }),
      2500
    );
  };

  const pickMention = (candidate) => {
    setInput((v) => v.replace(/@([\wÀ-ÿ'’.-]*)$/, `@${candidate.displayName} `));
    setMentions((prev) =>
      prev.some((m) => m.uid === candidate.uid) ? prev : [...prev, candidate]
    );
    setMentionQuery(null);
  };

  const submit = () =>
    guardText(input.trim(), async () => {
      const text = input.trim();
      if (!text) return;
      setFailedText(null);

      if (editing) {
        await editMessage({ familyId: currentFamilyId, familyKey, uid, messageId: editing.id, text });
        setEditing(null);
      } else {
        // Solo le menzioni davvero rimaste nel testo: cancellare il nome e
        // lasciare la notifica sarebbe un avviso senza motivo.
        const used = mentions.filter((m) => text.includes(`@${m.displayName}`));
        await sendText({
          familyId: currentFamilyId,
          familyKey,
          uid,
          senderName: displayName,
          text,
          replyToId: replyTo?.id || null,
          mentions: used,
        });
        setReplyTo(null);
        setMentions([]);
      }
      setInput("");
      setTyping({ familyId: currentFamilyId, uid, displayName, isTyping: false });
    });

  const sendFiles = (files) =>
    guard(async () => {
      const list = Array.from(files).slice(0, MAX_GROUP_ITEMS);
      if (!list.length) return;

      const prepared = await Promise.all(
        list.map(async (file) => ({
          blob: file.type.startsWith("video/") ? file : await compressPhoto(file),
          type: file.type.startsWith("video/") ? "video" : "photo",
        }))
      );

      if (prepared.length === 1) {
        await sendMedia({
          familyId: currentFamilyId,
          familyKey,
          uid,
          senderName: displayName,
          type: prepared[0].type,
          blob: prepared[0].blob,
          replyToId: replyTo?.id || null,
          onProgress: setProgress,
        });
      } else {
        await sendMediaGroup({
          familyId: currentFamilyId,
          familyKey,
          uid,
          senderName: displayName,
          items: prepared,
          replyToId: replyTo?.id || null,
          onProgress: setProgress,
        });
      }
      setReplyTo(null);
    });

  const sendDocumentFile = (file) =>
    guard(async () => {
      await sendMedia({
        familyId: currentFamilyId,
        familyKey,
        uid,
        senderName: displayName,
        type: "document",
        blob: file,
        fileName: file.name,
        replyToId: replyTo?.id || null,
        onProgress: setProgress,
      });
      setReplyTo(null);
    });

  const shareLocation = () =>
    guard(
      () =>
        new Promise((resolve, reject) => {
          navigator.geolocation.getCurrentPosition(
            async (pos) => {
              try {
                await sendLocation({
                  familyId: currentFamilyId,
                  familyKey,
                  uid,
                  senderName: displayName,
                  latitude: pos.coords.latitude,
                  longitude: pos.coords.longitude,
                  replyToId: replyTo?.id || null,
                });
                setReplyTo(null);
                resolve();
              } catch (err) {
                reject(err);
              }
            },
            () => reject(new Error(c.locationDenied))
          );
        })
    );

  /* ── Registrazione vocale ─────────────────────────────────────────────── */

  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      // Safari registra m4a, gli altri webm: si prende il formato migliore che
      // il browser dichiara di saper produrre.
      const mime = MediaRecorder.isTypeSupported("audio/mp4") ? "audio/mp4" : "audio/webm";
      const rec = new MediaRecorder(stream, { mimeType: mime });
      const chunks = [];
      const startedAt = Date.now();

      rec.ondataavailable = (e) => chunks.push(e.data);
      rec.onstop = async () => {
        stream.getTracks().forEach((track) => track.stop());
        if (recordingCancelled.current) return;
        const blob = new Blob(chunks, { type: mime });
        await guard(() =>
          sendMedia({
            familyId: currentFamilyId,
            familyKey,
            uid,
            senderName: displayName,
            type: "audio",
            blob,
            fileName: mime === "audio/mp4" ? "audio.m4a" : "audio.webm",
            durationSeconds: (Date.now() - startedAt) / 1000,
            replyToId: replyTo?.id || null,
            onProgress: setProgress,
          })
        );
        setReplyTo(null);
      };

      recordingCancelled.current = false;
      rec.start();
      setRecorder(rec);
      setRecordingSeconds(0);
    } catch {
      setError(c.micDenied);
    }
  };

  useEffect(() => {
    if (!recorder) return undefined;
    const id = setInterval(() => setRecordingSeconds((s) => s + 1), 1000);
    return () => clearInterval(id);
  }, [recorder]);

  const stopRecording = (cancel) => {
    if (!recorder) return;
    recordingCancelled.current = cancel;
    recorder.stop();
    setRecorder(null);
  };

  /* ── Messaggi: azioni singole ─────────────────────────────────────────── */

  const jumpTo = (messageId) => {
    setHighlighted(messageId);
    document.getElementById(`msg-${messageId}`)?.scrollIntoView({ block: "center", behavior: "smooth" });
    setTimeout(() => setHighlighted(null), 1600);
  };

  const loadOlder = () =>
    guard(async () => {
      if (!oldestDoc || loadingOlder) return;
      setLoadingOlder(true);
      try {
        const res = await fetchOlderMessages({ familyId: currentFamilyId, familyKey, beforeDoc: oldestDoc });
        setMessages((prev) => [...res.messages, ...prev]);
        setOldestDoc(res.oldestDoc);
        setHasMore(res.hasMore && !!res.oldestDoc);
      } finally {
        setLoadingOlder(false);
      }
    });

  const runSave = (target, message) =>
    guard(async () => {
      switch (target) {
        case "todo":
          await saveAsTodo({ familyId: currentFamilyId, uid, title: message.text.split("\n")[0] });
          break;
        case "event":
          await saveAsEvent({ familyId: currentFamilyId, uid, title: message.text.split("\n")[0] });
          break;
        case "grocery":
          await saveAsGrocery({ familyId: currentFamilyId, uid, name: message.text.split("\n")[0] });
          break;
        case "note":
          await saveAsNote({ familyId: currentFamilyId, uid, displayName, text: message.text });
          break;
        case "documents":
          await saveToDocuments({ familyId: currentFamilyId, uid, message });
          break;
        case "photos":
          await saveToPhotos({ familyId: currentFamilyId, uid, message });
          break;
        default:
          break;
      }
      setSaveTarget(null);
      setNotice(c.saved);
    });

  /* ── Render ───────────────────────────────────────────────────────────── */

  if (!chatEnabled) {
    return (
      <div className="chat-page">
        <header className="pw-header">
          <h1>{c.title}</h1>
        </header>
        <p className="pw-hint">{c.disabled}</p>
      </div>
    );
  }

  return (
    <div className="chat-page">
      <header className="pw-header chat-header">
        <h1>{c.title}</h1>
        <div className="chat-header-actions">
          {searchOpen && (
            <input
              className="chat-search"
              autoFocus
              placeholder={c.searchPlaceholder}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              onBlur={() => !search && setSearchOpen(false)}
            />
          )}

          {/* Quattro comandi in fila occupavano mezza intestazione per cose che
              si usano di rado: stanno sotto un solo «⋯», come il menu in cima
              alla chat su iOS. */}
          <div className="chat-header-menu" ref={headerMenuRef}>
            <button
              className="chat-header-menu-btn"
              title={c.actions}
              onClick={() => setHeaderMenuOpen((v) => !v)}
            >
              ⋯
            </button>

            {headerMenuOpen && (
              <div className="chat-menu">
                <button
                  onClick={() => {
                    setHeaderMenuOpen(false);
                    setSearchOpen(true);
                  }}
                >
                  🔍 {c.search}
                </button>
                <button
                  onClick={() => {
                    setHeaderMenuOpen(false);
                    setGalleryOpen(true);
                  }}
                >
                  🖼 {c.gallery}
                </button>
                <button
                  onClick={() => {
                    setHeaderMenuOpen(false);
                    setSelecting((v) => !v);
                    setSelectedIds([]);
                  }}
                >
                  ☑️ {selecting ? c.cancel : c.select}
                </button>
                <button
                  className="danger"
                  onClick={() => {
                    setHeaderMenuOpen(false);
                    if (!window.confirm(c.clearConfirm)) return;
                    guard(() => clearChat({ familyId: currentFamilyId, uid, messages: visible }));
                  }}
                >
                  🗑 {c.clear}
                </button>
              </div>
            )}
          </div>
        </div>
      </header>

      {error && (
        <p className="error">
          {error}
          {failedText && (
            <button
              className="link-btn"
              onClick={() => {
                setInput(failedText);
                setFailedText(null);
                setError(null);
              }}
            >
              {c.retry}
            </button>
          )}
        </p>
      )}
      {notice && (
        <p className="docs-notice">
          {notice}
          <button className="link-btn" onClick={() => setNotice(null)}>✕</button>
        </p>
      )}
      {progress !== null && (
        <p className="docs-busy">{c.uploading} {Math.round(progress * 100)}%</p>
      )}

      <div
        className={`chat-list${dragOver ? " drag-over" : ""}`}
        ref={listRef}
        onScroll={(e) => {
          const el = e.currentTarget;
          setAtBottom(el.scrollHeight - el.scrollTop - el.clientHeight < 80);
        }}
        onDragOver={(e) => {
          e.preventDefault();
          setDragOver(true);
        }}
        onDragLeave={() => setDragOver(false)}
        onDrop={(e) => {
          e.preventDefault();
          setDragOver(false);
          const files = Array.from(e.dataTransfer.files);
          if (!files.length) return;
          // Un documento trascinato resta un documento: solo foto e video
          // finiscono nella galleria.
          if (files.every((f) => f.type.startsWith("image/") || f.type.startsWith("video/"))) {
            sendFiles(files);
          } else {
            files.forEach(sendDocumentFile);
          }
        }}
      >
        {hasMore && oldestDoc && (
          <button className="chat-load-older" disabled={loadingOlder} onClick={loadOlder}>
            {loadingOlder ? c.loading : c.loadOlder}
          </button>
        )}

        {visible.map((message, index) => {
          const showDay = !sameDay(visible[index - 1]?.createdAt, message.createdAt);
          const replied = message.replyToId ? byId.get(message.replyToId) : null;

          return (
            <Fragment key={message.id}>
              {showDay && message.createdAt && (
                <div className="chat-day">{dayLabel(message.createdAt, locale, c)}</div>
              )}
              <div className="chat-item">
              {selecting && (
                <label className="chat-select">
                  <input
                    type="checkbox"
                    checked={selectedIds.includes(message.id)}
                    onChange={(e) =>
                      setSelectedIds((prev) =>
                        e.target.checked ? [...prev, message.id] : prev.filter((id) => id !== message.id)
                      )
                    }
                  />
                </label>
              )}
              <ChatBubble
                message={message}
                isMine={message.senderId === uid}
                locale={locale}
                labels={c}
                memberCount={members.length}
                highlighted={highlighted === message.id}
                repliedTo={
                  replied
                    ? { id: replied.id, senderName: replied.senderName, preview: previewOf(replied) }
                    : null
                }
                onReply={() => setReplyTo(message)}
                onEdit={() => {
                  setEditing(message);
                  setInput(message.text || "");
                }}
                onDelete={() =>
                  guard(() => deleteForEveryone({ familyId: currentFamilyId, uid, message }))
                }
                onDeleteForMe={() =>
                  guard(() => deleteForMe({ familyId: currentFamilyId, messageId: message.id, uid }))
                }
                onReact={(emoji) =>
                  guard(() =>
                    toggleReaction({
                      familyId: currentFamilyId,
                      messageId: message.id,
                      reactions: message.reactions,
                      emoji,
                      uid,
                    })
                  )
                }
                onSave={() => setSaveTarget(message)}
                onOpenMedia={setLightbox}
                onJumpTo={jumpTo}
              />
              </div>
            </Fragment>
          );
        })}
        <div ref={bottomRef} />
      </div>

      {!atBottom && (
        <button
          className="chat-scroll-bottom"
          onClick={() => bottomRef.current?.scrollIntoView({ behavior: "smooth", block: "end" })}
        >
          ↓
        </button>
      )}

      {selecting && selectedIds.length > 0 && (
        <div className="chat-selection-bar">
          <span>{selectedIds.length} {c.selected}</span>
          <button
            className="link-btn"
            onClick={() =>
              guard(async () => {
                for (const id of selectedIds) {
                  await deleteForMe({ familyId: currentFamilyId, messageId: id, uid });
                }
                setSelectedIds([]);
              })
            }
          >
            {c.deleteForMe}
          </button>
          <button
            className="link-btn danger"
            onClick={() =>
              guard(async () => {
                for (const id of selectedIds) {
                  const message = byId.get(id);
                  if (message?.senderId === uid) {
                    await deleteForEveryone({ familyId: currentFamilyId, uid, message });
                  }
                }
                setSelectedIds([]);
              })
            }
          >
            {c.deleteForEveryone}
          </button>
        </div>
      )}

      {typingUsers.length > 0 && (
        <p className="chat-typing">{typingUsers.join(", ")} {c.isTyping}</p>
      )}

      {(replyTo || editing) && (
        <div className="chat-context-bar">
          <span>
            <strong>{editing ? c.editing : `${c.replyingTo} ${replyTo.senderName}`}</strong>
            <small>{previewOf(editing || replyTo)}</small>
          </span>
          <button
            className="link-btn"
            onClick={() => {
              setReplyTo(null);
              setEditing(null);
              setInput("");
            }}
          >
            ✕
          </button>
        </div>
      )}

      {mentionCandidates.length > 0 && (
        <div className="chat-mentions">
          {mentionCandidates.map((candidate) => (
            <button key={candidate.uid} onClick={() => pickMention(candidate)}>
              @{candidate.displayName}
            </button>
          ))}
        </div>
      )}

      <div className="chat-composer">
        {/* Un solo «+» invece di cinque icone in fila, come nella chat del
            telefono: le voci sono le stesse, ma la barra torna a essere una
            riga per scrivere e non una barra degli strumenti. */}
        <div className="chat-attach" ref={attachRef}>
          <button
            className={`chat-plus${attachOpen ? " open" : ""}`}
            title={c.attach}
            onClick={() => setAttachOpen((v) => !v)}
          >
            +
          </button>

          {attachOpen && (
            <div className="chat-attach-menu">
              {[
                ["file", "📁", c.attachDocument, () => docInput.current?.click()],
                ["media", "🖼", c.attachMedia, () => mediaInput.current?.click()],
                ["camera", "📷", c.camera, () => cameraInput.current?.click()],
                ["location", "📍", c.sendLocation, shareLocation],
                [
                  "contact",
                  "👤",
                  c.sendContact,
                  () => setContactDraft({ givenName: "", familyName: "", phone: "", email: "" }),
                ],
              ].map(([key, icon, label, action]) => (
                <button
                  key={key}
                  className={`chat-attach-item ${key}`}
                  onClick={() => {
                    setAttachOpen(false);
                    action();
                  }}
                >
                  <span className="chat-attach-icon">{icon}</span>
                  {label}
                </button>
              ))}
            </div>
          )}
        </div>

        <input
          ref={mediaInput}
          type="file"
          accept="image/*,video/*"
          multiple
          hidden
          onChange={(e) => {
            const files = e.target.files;
            e.target.value = "";
            sendFiles(files);
          }}
        />
        <input
          ref={cameraInput}
          type="file"
          accept="image/*"
          capture="environment"
          hidden
          onChange={(e) => {
            const files = e.target.files;
            e.target.value = "";
            sendFiles(files);
          }}
        />
        <input
          ref={docInput}
          type="file"
          hidden
          onChange={(e) => {
            const file = e.target.files?.[0];
            e.target.value = "";
            if (file) sendDocumentFile(file);
          }}
        />

        <div className="chat-field">
          <textarea
            className="chat-input"
            rows={1}
            placeholder={c.placeholder}
            value={input}
            disabled={busy || !familyKey}
            onChange={(e) => onInputChange(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                submit();
              }
            }}
          />

          <div className="chat-emoji" ref={emojiRef}>
            <button className="chat-emoji-btn" title={c.emoji} onClick={() => setEmojiOpen((v) => !v)}>
              🙂
            </button>
            {emojiOpen && (
              <div className="chat-emoji-panel">
                {EMOJI_PALETTE.map((emoji) => (
                  <button
                    key={emoji}
                    onClick={() => {
                      onInputChange(input + emoji);
                      setEmojiOpen(false);
                    }}
                  >
                    {emoji}
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>

        {recorder ? (
          <>
            <span className="chat-recording">● {recordingSeconds}s</span>
            <button className="chat-round-btn" title={c.cancel} onClick={() => stopRecording(true)}>✕</button>
            <button className="chat-round-btn send" title={c.sendAudio} onClick={() => stopRecording(false)}>
              ➤
            </button>
          </>
        ) : input.trim() ? (
          <button
            className="chat-round-btn send"
            disabled={busy}
            title={editing ? c.saveEdit : c.send}
            onClick={submit}
          >
            ➤
          </button>
        ) : (
          <button className="chat-round-btn" title={c.recordAudio} onClick={startRecording}>🎤</button>
        )}
      </div>

      {galleryOpen && (
        <ChatMediaGallery
          familyId={currentFamilyId}
          familyKey={familyKey}
          labels={c}
          onClose={() => setGalleryOpen(false)}
          onGoToMessage={(id) => {
            setGalleryOpen(false);
            jumpTo(id);
          }}
        />
      )}

      {saveTarget && (
        <Modal onClose={() => setSaveTarget(null)}>
          <div className="modal-header">
            <strong>{c.saveTo}</strong>
            <button className="modal-icon-btn" onClick={() => setSaveTarget(null)}>✕</button>
          </div>
          <div className="chat-save-targets">
            {(saveTarget.type === "text"
              ? [["todo", `✅ ${c.saveTodo}`], ["event", `📅 ${c.saveEvent}`], ["grocery", `🛒 ${c.saveGrocery}`], ["note", `📝 ${c.saveNote}`]]
              : [["documents", `📁 ${c.saveDocuments}`], ...(saveTarget.type === "photo" || saveTarget.type === "video" ? [["photos", `🖼 ${c.savePhotos}`]] : [])]
            ).map(([key, label]) => (
              <button key={key} className="prof-action" disabled={busy} onClick={() => runSave(key, saveTarget)}>
                {label}
              </button>
            ))}
          </div>
        </Modal>
      )}

      {contactDraft && (
        <Modal onClose={() => setContactDraft(null)}>
          <div className="modal-header">
            <strong>{c.sendContact}</strong>
            <button className="modal-icon-btn" onClick={() => setContactDraft(null)}>✕</button>
          </div>
          <div className="chat-contact-form">
            {["givenName", "familyName", "phone", "email"].map((field) => (
              <label key={field}>
                {c[field]}
                <input
                  value={contactDraft[field]}
                  onChange={(e) => setContactDraft({ ...contactDraft, [field]: e.target.value })}
                />
              </label>
            ))}
            <button
              className="pw-btn-primary"
              disabled={busy || !contactDraft.givenName.trim()}
              onClick={() =>
                guard(async () => {
                  await sendContact({
                    familyId: currentFamilyId,
                    familyKey,
                    uid,
                    senderName: displayName,
                    contact: {
                      givenName: contactDraft.givenName,
                      familyName: contactDraft.familyName,
                      phoneNumbers: contactDraft.phone ? [{ label: "", value: contactDraft.phone }] : [],
                      emailAddresses: contactDraft.email ? [{ label: "", value: contactDraft.email }] : [],
                    },
                    replyToId: replyTo?.id || null,
                  });
                  setContactDraft(null);
                  setReplyTo(null);
                })
              }
            >
              {c.send}
            </button>
          </div>
        </Modal>
      )}

      {lightbox && (
        <Modal onClose={() => setLightbox(null)}>
          <img className="chat-lightbox" src={lightbox.url} alt="" />
          {lightbox.message?.senderId === uid && lightbox.message.type === "mediaGroup" && (
            <button
              className="prof-action danger"
              disabled={busy}
              onClick={() =>
                guard(async () => {
                  await removeFromGroup({
                    familyId: currentFamilyId,
                    uid,
                    message: lightbox.message,
                    index: lightbox.index,
                  });
                  setLightbox(null);
                })
              }
            >
              🗑 {c.removeFromGroup}
            </button>
          )}
        </Modal>
      )}
    </div>
  );
}
