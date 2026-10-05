import { useEffect, useMemo, useRef, useState } from "react";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { useChildren } from "../hooks/useChildren";
import { usePlan } from "../hooks/usePlan";
import {
  askAssistant,
  compactionStep,
  currentScopeId,
  deleteConversation,
  fetchUsage,
  listenConversations,
  recentPayload,
  saveConversation,
  startNewSession,
  summarizeConversation,
  SUMMARY_PREFIX,
} from "../services/aiChat";
import { loadMemorySnapshot, planContext } from "../services/memoryBook";
import { loadSettings, setHealthContextSendPreference } from "../services/settings";
import { executeActions, processReply } from "../services/aiActions";
import { extractAndStore } from "../services/aiMemory";
import { loadFamilyKey } from "../services/familyKey";
import { aiMessageSent } from "../services/analytics";
import { collection, getDocs, query, where } from "firebase/firestore";
import { db } from "../firebase";
import MarkdownText from "../components/MarkdownText";
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

/**
 * L'assistente unico. Non è più una voce della barra laterale: lo apre il
 * pulsante flottante (`AIFab`) montato dal `Layout`, in un pannello a destra
 * (`variant="panel"`), e da Salute lo aprono i pulsanti di salute, visite ed
 * esami con un `focus` sulla persona. La rotta `/assistente` resta per i
 * vecchi link e mostra la stessa chat a tutta pagina.
 *
 * Il contesto è il quaderno di schede (`memoryBook.js`), ricostruito a ogni
 * domanda; disegno in `internal/assistente-unico.md`.
 *
 * Nel pannello non c'è spazio per storico e chat affiancati: lo storico prende
 * il posto della chat finché non si sceglie una sessione.
 */
export default function Assistente({ variant = "page", onClose, focus = null, onClearFocus }) {
  const isPanel = variant === "panel";
  const { currentFamilyId, currentFamily } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();
  const a = t.assistant;
  const members = useFamilyMembers(currentFamilyId);
  const children = useChildren(currentFamilyId);
  const currentPlan = usePlan({ familyId: currentFamilyId, uid: user?.uid });

  const [conversations, setConversations] = useState([]);
  /** null = sessione corrente; altrimenti il docId di un archivio in lettura. */
  const [openArchiveId, setOpenArchiveId] = useState(null);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState(null);
  const [usage, setUsage] = useState(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [actionSummary, setActionSummary] = useState(null);
  /** Domanda in attesa della scelta «accurata / ridotta»: `{ text, plan }`. */
  const [pendingChoice, setPendingChoice] = useState(null);
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

  /**
   * Prepara il contesto e decide quanto mandare. Se il quaderno completo sta in
   * un messaggio parte subito; se no vale la stessa preferenza della chat
   * Salute (`aiPrefs.healthContextSendPreference`), e con «Chiedi ogni volta»
   * la domanda aspetta la scelta senza essere ancora salvata.
   */
  const send = async (preset) => {
    const text = (preset ?? draft).trim();
    if (!text || sending || !currentFamilyId || !user) return;

    setError(null);
    setSending(true);
    setDraft("");
    try {
      const snapshot = await loadMemorySnapshot({
        familyId: currentFamilyId,
        userId: user.uid,
        familyName: currentFamily?.name || "la famiglia",
        members,
        children,
      });
      const plan = planContext(snapshot, {
        question: text,
        focus,
        history: recentPayload(current?.messages ?? []),
        locale,
      });
      if (!plan.reducedPrompt || plan.fullUnits <= 1) {
        await deliver(text, plan.fullPrompt);
        return;
      }
      // Ridotto senza chiedere, qualunque sia la preferenza: sul Free, dove i
      // messaggi sono 5 in tutto, e quando il completo costerebbe più dei
      // messaggi rimasti (il server lo rifiuterebbe per intero). Come su iOS e
      // Android.
      const remaining = usage?.dailyLimit ? usage.dailyLimit - usage.usageToday : null;
      if (usage?.period === "lifetime" || (remaining !== null && remaining < plan.fullUnits)) {
        await deliver(text, plan.reducedPrompt);
        return;
      }
      const preference = await loadSettings(user.uid)
        .then((st) => st.healthContextSendPreference)
        .catch(() => "ask_each_time");
      if (preference === "full_accuracy") await deliver(text, plan.fullPrompt);
      else if (preference === "compact_summary") await deliver(text, plan.reducedPrompt);
      else {
        setPendingChoice({ text, plan });
        setSending(false);
      }
    } catch (err) {
      setError(err.message || a.genericError);
      setSending(false);
    }
  };

  /** Scelta dal riquadro: diventa la preferenza, come sul telefono. */
  const choose = async (mode) => {
    const choice = pendingChoice;
    if (!choice || !user) return;
    setPendingChoice(null);
    setSending(true);
    setHealthContextSendPreference(user.uid, mode).catch(() => {});
    try {
      await deliver(
        choice.text,
        mode === "full_accuracy" ? choice.plan.fullPrompt : choice.plan.reducedPrompt
      );
    } catch (err) {
      setError(err.message || a.genericError);
      setSending(false);
    }
  };

  /** Annullato: la domanda torna nel campo, non si perde. */
  const cancelChoice = () => {
    if (pendingChoice && !draft.trim()) setDraft(pendingChoice.text);
    setPendingChoice(null);
  };

  /** `prompt` = `{ stable, volatile }` da `planContext`: due blocchi di cache sul server. */
  const deliver = async (text, prompt) => {
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

      const result = await askAssistant({
        messages: recentPayload(history),
        systemPromptStable: prompt.stable,
        systemPrompt: prompt.volatile,
        familyId: currentFamilyId,
        purpose: "familyAgent",
      });
      // Come su iOS e Android: col focus di Salute vale come la vecchia chat
      // Salute, così la serie dell'evento resta confrontabile con quella di prima.
      aiMessageSent(focus ? "salute" : "assistente", currentPlan || "unknown");

      // Il blocco azioni si esegue e sparisce dal testo, come su iOS: nella
      // chat resta solo quello che l'utente deve leggere.
      const { displayText, actions } = processReply(result.reply);
      if (actions.length) {
        // Il to-do creato da Salute va alla persona del focus, se è un figlio.
        const focusChild = children.find((c) => c.id === focus?.personId);
        const summary = await executeActions({
          actions,
          familyId: currentFamilyId,
          uid: user.uid,
          userName: user.displayName ?? null,
          defaultChildId: focusChild?.id ?? children[0]?.id ?? "",
          pendingGroceryNames: await pendingGroceryNames(currentFamilyId),
          loadFamilyKey: () =>
            loadFamilyKey({ familyId: currentFamilyId, userId: user.uid }),
          defaultListName: t.todo.defaultListName,
          members,
          familyName: currentFamily?.name || "",
          requestTexts: t.requests,
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

  const focusLabel = focus
    ? focus.scope === "visits"
      ? a.focusVisits(focus.personName)
      : focus.scope === "exams"
        ? a.focusExams(focus.personName)
        : a.focusHealth(focus.personName)
    : null;
  const focusSuggestions = focus
    ? focus.scope === "visits"
      ? a.suggestVisits(focus.personName)
      : focus.scope === "exams"
        ? a.suggestExams(focus.personName)
        : a.suggestPerson(focus.personName)
    : [];

  const quotaLabel = useMemo(() => {
    if (!usage || !usage.dailyLimit) return null;
    return a.quota(usage.usageToday, usage.dailyLimit);
  }, [usage, a]);

  return (
    <div className={"ai-page" + (isPanel ? " ai-panel" : "")}>
      <header className="pw-header">
        {isPanel ? <h2>{a.fabLabel}</h2> : <h1>{a.title}</h1>}
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
          {isPanel && (
            <button className="ai-panel-close" onClick={onClose} aria-label={a.close} title={a.close}>
              ✕
            </button>
          )}
        </div>
      </header>

      {error && <p className="error">{error}</p>}

      <div className="ai-layout">
        {historyOpen && (
          <aside className="ai-history">
            <button
              className={"ai-history-item" + (isArchive ? "" : " active")}
              onClick={() => {
                setOpenArchiveId(null);
                if (isPanel) setHistoryOpen(false);
              }}
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
                    onClick={() => {
                      setOpenArchiveId(conversation.docId);
                      if (isPanel) setHistoryOpen(false);
                    }}
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

        <section className="ai-chat" hidden={isPanel && historyOpen}>
          {isArchive && (
            <div className="ai-archive-banner">
              {a.archiveBanner}
              <button className="link-btn" onClick={() => setOpenArchiveId(null)}>
                {a.backToCurrent}
              </button>
            </div>
          )}

          {focusLabel && !isArchive && (
            <div className="ai-focus-chip">
              <span>🩺 {focusLabel}</span>
              <button
                className="link-btn"
                onClick={onClearFocus}
                aria-label={a.focusClear}
                title={a.focusClear}
              >
                ✕
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
                <p>{focus ? a.focusHint : a.emptyHint}</p>
                {focusSuggestions.length > 0 && (
                  <div className="ai-suggestions">
                    {focusSuggestions.map((q) => (
                      <button key={q} className="ai-suggestion" onClick={() => send(q)}>
                        {q}
                      </button>
                    ))}
                  </div>
                )}
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
                  <div className="ai-bubble">
                    {/* Come nella chat di Salute: la risposta arriva in
                        Markdown, la domanda è il testo digitato. */}
                    {m.role === "assistant" ? <MarkdownText text={m.content} /> : m.content}
                  </div>
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

          {pendingChoice && !isArchive && (
            <div className="ai-choice" role="dialog" aria-label={a.choiceTitle}>
              <strong>{a.choiceTitle}</strong>
              <p>{a.choiceMessage}</p>
              <div className="ai-choice-actions">
                <button className="pw-btn-primary" onClick={() => choose("full_accuracy")}>
                  {a.choiceFull(pendingChoice.plan.fullUnits)}
                </button>
                <button className="docs-btn" onClick={() => choose("compact_summary")}>
                  {a.choiceReduced(pendingChoice.plan.reducedUnits)}
                </button>
                <button className="link-btn" onClick={cancelChoice}>
                  {a.choiceCancel}
                </button>
              </div>
            </div>
          )}

          {/* La conversazione è una sola e quasi mai vuota: aperto da Salute, i
              suggerimenti a tema restano sopra il campo anche con lo storico. */}
          {focusSuggestions.length > 0 && messages.length > 0 && !isArchive && !pendingChoice && (
            <div className="ai-suggestions ai-suggestions-row">
              {focusSuggestions.map((q) => (
                <button key={q} className="ai-suggestion" disabled={sending} onClick={() => send(q)}>
                  {q}
                </button>
              ))}
            </div>
          )}

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
                disabled={sending || Boolean(pendingChoice)}
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
