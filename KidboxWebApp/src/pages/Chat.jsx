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
import ChatBubble, { ChatUploadBubble } from "../components/ChatBubble";
import { formatDuration } from "../components/chatFormat";
import ChatMediaGallery from "../components/ChatMediaGallery";
import RecordingWave from "../components/RecordingWave";
import Modal from "../components/Modal";
import {
  MAX_GROUP_ITEMS,
  clearChat,
  clearTyping,
  deleteForEveryone,
  deleteForMe,
  editMessage,
  fetchOlderMessages,
  isUploadCancelled,
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
  draftFromDataTransfer,
  draftFromTransferText,
  findVCardFile,
  vCardToDraft,
} from "../services/vcard";
import {
  saveAsEvent,
  saveAsGrocery,
  saveAsNote,
  saveAsTodo,
  saveToDocuments,
  saveToPhotos,
} from "../services/chatSave";
import "./Chat.css";

/**
 * Scrivania (Mac compreso): mouse e trascinamento ci sono davvero. È la sola
 * distinzione che serve — l'import vCard vive di drag&drop e di ⌘V, che sul
 * telefono non esistono.
 */
const IS_DESKTOP =
  typeof window !== "undefined" && window.matchMedia?.("(hover: hover) and (pointer: fine)").matches;

/**
 * Formati di registrazione, dal più interoperabile al ripiego.
 *
 * L'AAC in contenitore MP4 è la sola cosa che iPhone, Android e browser sanno
 * leggere tutti: è quello che registrano i due client nativi, ed è quello che
 * si prova per primo. Chrome sa produrlo dalla 130, Safari da sempre; su
 * Firefox si ripiega su WebM/Opus, che il telefono non riproduce — meglio di
 * niente, e almeno il file dichiara quello che è.
 */
const AUDIO_MIME_PREFERENCE = [
  "audio/mp4;codecs=mp4a.40.2",
  "audio/mp4",
  "audio/webm;codecs=opus",
  "audio/webm",
];

/** Estensione coerente col contenitore: la usano i client nativi per capire
 *  che cosa stanno scaricando. */
const audioExtension = (mime) => (mime.includes("mp4") ? "m4a" : "webm");

/** Sotto questa soglia non c'è un messaggio: c'è un tocco. */
const MIN_RECORDING_SECONDS = 0.6;

/** Foto ridotta prima dell'invio, come fa `compressPhoto` su iOS. */
/**
 * Foto ridimensionata per l'invio, con le dimensioni finali. createImageBitmap
 * applica già l'orientamento EXIF, quindi larghezza e altezza sono quelle che
 * si vedono.
 */
async function compressPhoto(file) {
  if (!file.type.startsWith("image/")) return { blob: file, width: null, height: null };
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
    return { blob: blob || file, width: canvas.width, height: canvas.height };
  } catch {
    // Formato che il browser non sa decodificare: si manda l'originale.
    return { blob: file, width: null, height: null };
  }
}

/** Dimensioni di un video letto dai metadati (il browser applica già la rotazione). */
function videoDimensions(file) {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file);
    const video = document.createElement("video");
    const done = (dims) => {
      URL.revokeObjectURL(url);
      resolve(dims);
    };
    video.preload = "metadata";
    video.onloadedmetadata = () =>
      done({ width: video.videoWidth || null, height: video.videoHeight || null });
    video.onerror = () => done({ width: null, height: null });
    video.src = url;
  });
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

  // Invii in corso, mostrati come bolle locali con anello e stop finché il
  // messaggio vero non arriva dal listener.
  const [pendingUploads, setPendingUploads] = useState([]);
  const [error, setError] = useState(null);
  const [notice, setNotice] = useState(null);
  const [busy, setBusy] = useState(false);

  const [galleryOpen, setGalleryOpen] = useState(false);
  const [saveTarget, setSaveTarget] = useState(null);
  const [contactDraft, setContactDraft] = useState(null);
  const [contactDropOver, setContactDropOver] = useState(false);
  const [contactImportError, setContactImportError] = useState(null);
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
  /** Lo stream in presa diretta: serve all'onda che scorre mentre si registra. */
  const [recordingStream, setRecordingStream] = useState(null);
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
  const vcardInput = useRef(null);
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
  }, [messages.length, pendingUploads.length, atBottom]);

  /* ── Dati derivati ────────────────────────────────────────────────────── */

  const visible = useMemo(
    () =>
      messages
        .filter((m) => !m.deletedFor.includes(uid))
        .filter((m) => !search.trim() || (m.text || "").toLowerCase().includes(search.toLowerCase())),
    [messages, uid, search]
  );

  const byId = useMemo(() => new Map(messages.map((m) => [m.id, m])), [messages]);

  // La bolla locale lascia il posto al messaggio vero appena il listener lo porta:
  // toglierla prima farebbe sparire il media per un attimo.
  useEffect(() => {
    const arrived = pendingUploads.filter((u) => u.done && byId.has(u.id));
    if (!arrived.length) return;
    arrived.forEach((u) => u.previewURL && URL.revokeObjectURL(u.previewURL));
    setPendingUploads((prev) => prev.filter((u) => !arrived.some((a) => a.id === u.id)));
  }, [pendingUploads, byId]);

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
      // Stop premuto nell'anello: è una scelta, non un errore.
      if (isUploadCancelled(err)) return true;
      setError(err.message);
      return false;
    } finally {
      setBusy(false);
    }
  };

  /**
   * Avvia un invio con la sua bolla locale. `run` riceve id del messaggio,
   * segnale di annullamento e callback di progresso; la bolla sparisce quando
   * il messaggio vero è arrivato, o subito se l'invio è fermato o fallisce.
   */
  const startUpload = async ({ previewBlob, ...meta }, run) => {
    const id = crypto.randomUUID();
    const controller = new AbortController();
    const previewURL = previewBlob ? URL.createObjectURL(previewBlob) : null;
    setPendingUploads((prev) => [
      ...prev,
      { ...meta, id, previewURL, progress: null, controller, createdAt: new Date(), done: false },
    ]);
    const patch = (changes) =>
      setPendingUploads((prev) => prev.map((u) => (u.id === id ? { ...u, ...changes } : u)));
    try {
      await run({ id, signal: controller.signal, onProgress: (p) => patch({ progress: p }) });
      patch({ done: true });
    } catch (err) {
      if (previewURL) URL.revokeObjectURL(previewURL);
      setPendingUploads((prev) => prev.filter((u) => u.id !== id));
      throw err;
    }
  };

  /** Come `guard`, ma tiene da parte il testo perché si possa riprovare. */
  const guardText = async (text, action) => {
    if (!(await guard(action))) setFailedText(text);
  };

  const EMPTY_CONTACT = { givenName: "", familyName: "", phone: "", email: "" };

  /**
   * Apre il form contatto. Dove il browser ha il picker di sistema — oggi solo
   * Chrome su Android — lo usiamo come su iOS; altrove, Mac compreso, non
   * esiste nessuna API che apra Contatti.app e restituisca la scheda, quindi
   * resta il form, che però si riempie da una vCard.
   */
  const openContactDraft = async () => {
    if (navigator.contacts?.select && window.ContactsManager) {
      try {
        const [picked] = await navigator.contacts.select(["name", "tel", "email"], { multiple: false });
        if (!picked) return;
        const full = (picked.name?.[0] || "").trim();
        const space = full.indexOf(" ");
        setContactImportError(null);
        setContactDraft({
          givenName: space < 0 ? full : full.slice(0, space),
          familyName: space < 0 ? "" : full.slice(space + 1),
          phone: picked.tel?.[0] || "",
          email: picked.email?.[0] || "",
        });
        return;
      } catch {
        // Picker negato o non utilizzabile: si prosegue col form.
      }
    }
    setContactImportError(null);
    setContactDraft(EMPTY_CONTACT);
  };

  /** Sostituisce il form con la vCard letta, o segnala che non lo era. */
  const applyVCardDraft = (draft) => {
    if (!draft) {
      setContactImportError(c.contactImportFailed);
      return;
    }
    setContactImportError(null);
    setContactDraft(draft);
  };

  /**
   * ⌘V sul form contatto. L'ascolto sta sul documento perché la scheda copiata
   * da Contatti.app va incollata anche quando il fuoco non è in un campo; un
   * incolla che non è una vCard resta un incolla normale.
   */
  useEffect(() => {
    if (!contactDraft) return undefined;
    const onPaste = (e) => {
      const draft = draftFromTransferText(e.clipboardData);
      if (draft) {
        e.preventDefault();
        applyVCardDraft(draft);
        return;
      }
      const file = findVCardFile(e.clipboardData);
      if (!file) return;
      e.preventDefault();
      file.text().then((text) => applyVCardDraft(vCardToDraft(text)));
    };
    document.addEventListener("paste", onPaste);
    return () => document.removeEventListener("paste", onPaste);
  }, [contactDraft]);

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
        list.map(async (file) =>
          file.type.startsWith("video/")
            ? { blob: file, type: "video", ...(await videoDimensions(file)) }
            : { type: "photo", ...(await compressPhoto(file)) }
        )
      );

      const replyToId = replyTo?.id || null;
      setReplyTo(null);
      const first = prepared[0];
      const single = prepared.length === 1;
      await startUpload(
        {
          type: single ? first.type : "mediaGroup",
          previewBlob: first.blob,
          previewType: first.type,
          width: single ? first.width : null,
          height: single ? first.height : null,
        },
        ({ id, signal, onProgress }) =>
          single
            ? sendMedia({
                familyId: currentFamilyId,
                familyKey,
                uid,
                senderName: displayName,
                type: first.type,
                blob: first.blob,
                width: first.width,
                height: first.height,
                replyToId,
                id,
                signal,
                onProgress,
              })
            : sendMediaGroup({
                familyId: currentFamilyId,
                familyKey,
                uid,
                senderName: displayName,
                items: prepared,
                replyToId,
                id,
                signal,
                onProgress,
              })
      );
    });

  const sendDocumentFile = (file) =>
    guard(async () => {
      const replyToId = replyTo?.id || null;
      setReplyTo(null);
      await startUpload({ type: "document", fileName: file.name }, ({ id, signal, onProgress }) =>
        sendMedia({
          familyId: currentFamilyId,
          familyKey,
          uid,
          senderName: displayName,
          type: "document",
          blob: file,
          fileName: file.name,
          replyToId,
          id,
          signal,
          onProgress,
        })
      );
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
      const preferred = AUDIO_MIME_PREFERENCE.find((m) => MediaRecorder.isTypeSupported(m));
      const rec = preferred
        ? new MediaRecorder(stream, { mimeType: preferred })
        : new MediaRecorder(stream);
      const chunks = [];
      const startedAt = Date.now();

      rec.ondataavailable = (e) => chunks.push(e.data);
      rec.onstop = async () => {
        stream.getTracks().forEach((track) => track.stop());
        setRecordingStream(null);
        if (recordingCancelled.current) return;
        // `rec.mimeType` e non la preferenza: è il browser a dire che cosa ha
        // prodotto davvero, e sul file va scritto quello.
        const mime = rec.mimeType || preferred || "audio/webm";
        const blob = new Blob(chunks, { type: mime });
        const seconds = (Date.now() - startedAt) / 1000;
        // Un vocale vuoto o di un decimo di secondo diventava una bolla che
        // nessun client riesce ad aprire: si ferma qui, dicendolo.
        if (!blob.size || seconds < MIN_RECORDING_SECONDS) {
          setError(c.recordingTooShort);
          return;
        }
        const replyToId = replyTo?.id || null;
        setReplyTo(null);
        await guard(() =>
          startUpload({ type: "audio", fileName: `🎤 ${formatDuration(seconds)}` }, ({ id, signal, onProgress }) =>
            sendMedia({
              familyId: currentFamilyId,
              familyKey,
              uid,
              senderName: displayName,
              type: "audio",
              blob,
              fileName: `audio.${audioExtension(mime)}`,
              durationSeconds: seconds,
              replyToId,
              id,
              signal,
              onProgress,
            })
          )
        );
      };

      recordingCancelled.current = false;
      rec.start();
      setRecorder(rec);
      setRecordingStream(stream);
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
          await saveAsTodo({
            familyId: currentFamilyId,
            uid,
            title: message.text.split("\n")[0],
            defaultListName: t.todo.defaultListName,
          });
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
        {pendingUploads
          .filter((u) => !byId.has(u.id))
          .map((u) => (
            <div className="chat-item" key={`upload-${u.id}`}>
              <ChatUploadBubble
                upload={u}
                locale={locale}
                labels={c}
                onCancel={() => u.controller.abort()}
              />
            </div>
          ))}
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
        {/* Mentre si registra la barra è tutta del vocale, come su WhatsApp:
            «+» e campo di scrittura escono di scena, così il tempo e l'onda
            hanno lo spazio della riga invece di un ritaglio in fondo. */}
        {!recorder && (
        <>
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
                  openContactDraft,
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

        </>
        )}

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

        {!recorder && (
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
        )}

        {recorder ? (
          <>
            <div className="chat-recorder">
              <span className="chat-recording">● {recordingSeconds}s</span>
              <RecordingWave stream={recordingStream} />
            </div>
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
          {IS_DESKTOP && (
          <div
            className={`chat-contact-drop ${contactDropOver ? "over" : ""}`}
            onDragOver={(e) => {
              e.preventDefault();
              e.stopPropagation();
              setContactDropOver(true);
            }}
            onDragLeave={() => setContactDropOver(false)}
            onDrop={async (e) => {
              e.preventDefault();
              e.stopPropagation();
              setContactDropOver(false);
              applyVCardDraft(await draftFromDataTransfer(e.dataTransfer));
            }}
          >
            <p className="chat-contact-drop-hint">{c.contactDropHint}</p>
            <button className="link-btn" onClick={() => vcardInput.current?.click()}>
              {c.contactPickFile}
            </button>
            <input
              ref={vcardInput}
              type="file"
              accept=".vcf,text/vcard,text/x-vcard"
              hidden
              onChange={async (e) => {
                const file = e.target.files?.[0];
                e.target.value = "";
                if (file) applyVCardDraft(vCardToDraft(await file.text()));
              }}
            />
            {contactImportError && <p className="chat-contact-drop-error">{contactImportError}</p>}
          </div>
          )}
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
