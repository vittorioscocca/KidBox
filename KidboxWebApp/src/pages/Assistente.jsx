import { useEffect, useMemo, useRef, useState } from "react";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { useChildren } from "../hooks/useChildren";
import {
  askAssistant,
  compactionStep,
  currentScopeId,
  deleteConversation,
  fetchUsage,
  listenConversations,
  saveConversation,
  startNewSession,
  summarizeConversation,
  SUMMARY_PREFIX,
} from "../services/aiChat";
import { buildSystemPrompt } from "../services/aiContext";
import { executeActions, processReply } from "../services/aiActions";
import { extractAndStore } from "../services/aiMemory";
import { loadFamilyKey } from "../services/familyKey";
import { collection, getDocs, query, where } from "firebase/firestore";
import { db } from "../firebase";
import "./Assistente.css";

const newId = () => crypto.randomUUID();

/**
 * Nomi già presenti nella lista della spesa: servono all'esecutore per non
 * aggiungere due volte lo stesso articolo, come fa `PlanningActionExecutor`.
 */
async function pendingGroceryNames(familyId) {
  try {
    const snap = await getDocs(
      query(collection(db, "families", familyId, "groceries"), where("isDeleted", "==", false))
    );
    return snap.docs
      .map((d) => d.data())
      .filter((g) => !g.isPurchased)
      .map((g) => g.name || "");
  } catch {
    return [];
  }
}

export default function Assistente() {
  const { currentFamilyId, currentFamily } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();
  const a = t.assistant;
  const members = useFamilyMembers(currentFamilyId);
  const children = useChildren(currentFamilyId);

  const [conversations, setConversations] = useState([]);
  /** null = sessione corrente; altrimenti il docId di un archivio in lettura. */
  const [openArchiveId, setOpenArchiveId] = useState(null);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState(null);
  const [usage, setUsage] = useState(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [actionSummary, setActionSummary] = useState(null);
  const scrollRef = useRef(null);
  /**
   * Ultimo scalino di quota a cui si è compattato. Vive quanto la pagina, come
   * la variabile in memoria del telefono: riaprire azzera, ed è voluto.
   */
  const lastCompactionStep = useRef(0);

  useEffect(() => {
    if (!currentFamilyId || !user) return undefined;
    return listenConversations({
      uid: user.uid,
      familyId: currentFamilyId,
      onChange: setConversations,
      onError: (err) => setError(err.message),
    });
  }, [currentFamilyId, user]);

  useEffect(() => {
    if (!currentFamilyId) return;
    fetchUsage(currentFamilyId)
      .then(setUsage)
      // Il contatore è un di più: se non arriva, la chat funziona lo stesso e
      // riempirla di errori per questo sarebbe rumore.
      .catch(() => setUsage(null));
  }, [currentFamilyId]);

  const scopeId = currentFamilyId ? currentScopeId(currentFamilyId) : null;
  const current = conversations.find((c) => c.scopeId === scopeId) || null;
  const archives = conversations.filter((c) => c.scopeId !== scopeId);
  const openArchive = archives.find((c) => c.docId === openArchiveId) || null;

  const shown = openArchive || current;
  const messages = shown?.messages ?? [];
  const isArchive = Boolean(openArchive);

  // Si scende in fondo a ogni messaggio nuovo: una chat che resta in cima
  // sembra non aver risposto.
  useEffect(() => {
    const box = scrollRef.current;
    if (box) box.scrollTop = box.scrollHeight;
  }, [messages.length, sending]);

  const fmtWhen = (millis) =>
    millis
      ? new Date(millis).toLocaleString(locale === "en" ? "en-US" : "it-IT", {
          day: "2-digit",
          month: "short",
          hour: "2-digit",
          minute: "2-digit",
        })
      : "";

  const titleOf = (conversation) => {
    const first = conversation.messages.find((m) => m.role === "user");
    if (!first) return a.emptySession;
    return first.content.length > 60 ? `${first.content.slice(0, 60)}…` : first.content;
  };

  const send = async () => {
    const text = draft.trim();
    if (!text || sending || !currentFamilyId || !user) return;

    setError(null);
    setSending(true);
    setDraft("");

    const outgoing = {
      id: newId(),
      role: "user",
      content: text,
      createdAt: Date.now(),
    };
    // La domanda si salva PRIMA di chiamare il modello: se la risposta fallisce
    // o la quota è finita, quello che l'utente ha scritto non deve sparire.
    const history = [...(current?.messages ?? []), outgoing];
    const createdAt = current?.createdAt || Date.now();

    try {
      await saveConversation({
        uid: user.uid,
        familyId: currentFamilyId,
        scopeId,
        messages: history,
        createdAt,
      });

      const systemPrompt = await buildSystemPrompt({
        familyId: currentFamilyId,
        userId: user.uid,
        familyName: currentFamily?.name || "la famiglia",
        members,
        children,
      });

      const result = await askAssistant({
        messages: history,
        systemPrompt,
        familyId: currentFamilyId,
      });

      // Il blocco azioni si esegue e sparisce dal testo, come su iOS: nella
      // chat resta solo quello che l'utente deve leggere.
      const { displayText, actions } = processReply(result.reply);
      if (actions.length) {
        const summary = await executeActions({
          actions,
          familyId: currentFamilyId,
          uid: user.uid,
          userName: user.displayName ?? null,
          defaultChildId: children[0]?.id ?? "",
          pendingGroceryNames: await pendingGroceryNames(currentFamilyId),
          loadFamilyKey: () =>
            loadFamilyKey({ familyId: currentFamilyId, userId: user.uid }),
        });
        setActionSummary(summary);
      }

      await saveConversation({
        uid: user.uid,
        familyId: currentFamilyId,
        scopeId,
        messages: [
          ...history,
          { id: newId(), role: "assistant", content: displayText, createdAt: Date.now() },
        ],
        createdAt,
      });
      setUsage({
        usageToday: result.usageToday,
        dailyLimit: result.dailyLimit,
        period: result.period,
      });

      await compactIfNeeded({
        messages: [
          ...history,
          { id: newId(), role: "assistant", content: displayText, createdAt: Date.now() },
        ],
        usageToday: result.usageToday,
        dailyLimit: result.dailyLimit,
        createdAt,
      });
    } catch (err) {
      setError(err.message || a.genericError);
    } finally {
      setSending(false);
    }
  };

  /**
   * Sostituisce la conversazione con un suo riassunto quando la quota consumata
   * supera le soglie di iOS. Serve a non trascinarsi dietro un contesto sempre
   * più lungo — che costa e confonde il modello.
   *
   * Prima di compattare la conversazione viene archiviata: sul telefono i
   * messaggi vecchi si perdono, qui restano leggibili nello storico. È la
   * stessa scelta di «Nuova sessione», e per lo stesso motivo.
   *
   * Se il riassunto fallisce non si tocca nulla: meglio una conversazione lunga
   * che una svuotata a metà.
   */
  const compactIfNeeded = async ({ messages: full, usageToday, dailyLimit, createdAt }) => {
    const step = compactionStep({
      usageToday,
      dailyLimit,
      lastStep: lastCompactionStep.current,
    });
    if (!step || full.length < 2) return;

    try {
      const summary = await summarizeConversation({
        messages: full,
        familyId: currentFamilyId,
      });

      await startNewSession({
        uid: user.uid,
        familyId: currentFamilyId,
        messages: full,
        createdAt,
      });
      await saveConversation({
        uid: user.uid,
        familyId: currentFamilyId,
        scopeId,
        messages: [
          {
            id: `${SUMMARY_PREFIX}${currentFamilyId}`,
            role: "assistant",
            content: summary,
            createdAt: Date.now(),
          },
        ],
        createdAt: Date.now(),
        summary,
      });
      lastCompactionStep.current = step;

      // Estrazione della memoria sui messaggi PRE-compattazione, come su iOS:
      // dopo, al loro posto, c'è solo il riassunto. Non si attende — è
      // manutenzione, e l'utente ha già la sua risposta.
      extractAndStore({
        familyId: currentFamilyId,
        messages: full,
        conversationId: scopeId,
        isSummary: (m) => Boolean(m.id?.startsWith(SUMMARY_PREFIX)),
      });
    } catch (err) {
      // Silenzioso di proposito: la risposta all'utente è già arrivata, e un
      // errore su un'operazione di manutenzione non deve sembrare un fallimento
      // della chat.
      console.warn("compattazione non riuscita:", err);
    }
  };

  const newSession = async () => {
    if (!current || !user) return;
    if (current.messages.length && !window.confirm(a.newSessionConfirm)) return;
    setError(null);
    try {
      await startNewSession({
        uid: user.uid,
        familyId: currentFamilyId,
        messages: current.messages,
        createdAt: current.createdAt,
      });
      setOpenArchiveId(null);
    } catch (err) {
      setError(err.message);
    }
  };

  const removeArchive = async (conversation) => {
    if (!window.confirm(a.deleteConfirm)) return;
    await deleteConversation({ uid: user.uid, docId: conversation.docId });
    if (openArchiveId === conversation.docId) setOpenArchiveId(null);
  };

  const quotaLabel = useMemo(() => {
    if (!usage || !usage.dailyLimit) return null;
    return a.quota(usage.usageToday, usage.dailyLimit);
  }, [usage, a]);

  return (
    <div className="ai-page">
      <header className="pw-header">
        <h1>{a.title}</h1>
        <div className="pw-toolbar">
          {quotaLabel && <span className="ai-quota">{quotaLabel}</span>}
          <button
            className={"docs-btn" + (historyOpen ? " active" : "")}
            onClick={() => setHistoryOpen((v) => !v)}
          >
            🕘 {a.history}
          </button>
          <button className="pw-btn-primary" onClick={newSession} disabled={!current}>
            ✨ {a.newSession}
          </button>
        </div>
      </header>

      {error && <p className="error">{error}</p>}

      <div className="ai-layout">
        {historyOpen && (
          <aside className="ai-history">
            <button
              className={"ai-history-item" + (isArchive ? "" : " active")}
              onClick={() => setOpenArchiveId(null)}
            >
              <span className="ai-history-title">{a.currentSession}</span>
              <span className="ai-history-meta">
                {current?.messages.length ? fmtWhen(current.updatedAt) : a.emptySession}
              </span>
            </button>

            {archives.length === 0 ? (
              <p className="pw-hint">{a.noHistory}</p>
            ) : (
              archives.map((conversation) => (
                <div
                  key={conversation.docId}
                  className={
                    "ai-history-item" +
                    (openArchiveId === conversation.docId ? " active" : "")
                  }
                >
                  <button
                    className="ai-history-open"
                    onClick={() => setOpenArchiveId(conversation.docId)}
                  >
                    <span className="ai-history-title">{titleOf(conversation)}</span>
                    <span className="ai-history-meta">
                      {fmtWhen(conversation.updatedAt)} ·{" "}
                      {a.messageCount(conversation.messages.length)}
                    </span>
                  </button>
                  <button
                    className="ai-history-delete"
                    title={a.delete}
                    onClick={() => removeArchive(conversation)}
                  >
                    🗑
                  </button>
                </div>
              ))
            )}
          </aside>
        )}

        <section className="ai-chat">
          {isArchive && (
            <div className="ai-archive-banner">
              {a.archiveBanner}
              <button className="link-btn" onClick={() => setOpenArchiveId(null)}>
                {a.backToCurrent}
              </button>
            </div>
          )}

          {actionSummary && (
            <div className="ai-action-summary">
              <span>✅ {actionSummary}</span>
              <button className="link-btn" onClick={() => setActionSummary(null)}>✕</button>
            </div>
          )}

          <div className="ai-messages" ref={scrollRef}>
            {messages.length === 0 && !sending ? (
              <div className="ai-empty">
                <div className="empty-icon">🧠</div>
                <strong>{a.emptyTitle}</strong>
                <p>{a.emptyHint}</p>
              </div>
            ) : (
              messages.map((m) => (
                <div key={m.id} className={"ai-msg " + m.role}>
                  {m.id?.startsWith(SUMMARY_PREFIX) && (
                    // Senza etichetta la chat sembrerebbe essersi svuotata da
                    // sola: qui si dice che cos'è quel messaggio e dov'è finito
                    // il resto.
                    <span className="ai-summary-label">{a.summaryLabel}</span>
                  )}
                  <div className="ai-bubble">{m.content}</div>
                  <span className="ai-time">{fmtWhen(m.createdAt)}</span>
                </div>
              ))
            )}
            {sending && (
              <div className="ai-msg assistant">
                <div className="ai-bubble thinking">
                  <span /><span /><span />
                </div>
              </div>
            )}
          </div>

          {!isArchive && (
            <form
              className="ai-composer"
              onSubmit={(e) => {
                e.preventDefault();
                send();
              }}
            >
              <textarea
                rows={1}
                placeholder={a.placeholder}
                value={draft}
                disabled={sending}
                onChange={(e) => setDraft(e.target.value)}
                onKeyDown={(e) => {
                  // Invio manda, Maiusc+Invio va a capo: è quello che ci si
                  // aspetta da una chat, non da un modulo.
                  if (e.key === "Enter" && !e.shiftKey) {
                    e.preventDefault();
                    send();
                  }
                }}
              />
              <button type="submit" disabled={sending || !draft.trim()}>
                {sending ? "…" : "➤"}
              </button>
            </form>
          )}
        </section>
      </div>
    </div>
  );
}
