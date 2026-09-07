/**
 * Chat AI di Salute, il pannello condiviso dai tre livelli (salute, visite,
 * analisi). Il contesto clinico non è un messaggio: viaggia come `systemPrompt`
 * a ogni chiamata, esattamente come sul telefono, così non consuma turni della
 * conversazione e resta aggiornato quando i dati cambiano.
 *
 * La conversazione è la **stessa** dell'iPhone, perché lo scope e l'id del
 * documento sono quelli di `KBAIConversation`. Quello che si scrive qui compare
 * là e viceversa.
 *
 * La quota la applica il server: qui si mostra solo il contatore che torna
 * indietro, senza fingere controlli di piano.
 */
import { useEffect, useRef, useState } from "react";
import { askAssistant } from "../../services/aiChat";
import MarkdownText from "../MarkdownText";
import {
  clearHealthConversation,
  listenHealthConversation,
  saveHealthConversation,
} from "../../services/healthChat";
import { newId } from "./shared";

export default function HealthAIChat({
  uid,
  familyId,
  kind,
  subjectId,
  scopeId,
  systemPrompt,
  title,
  h,
  onClose,
}) {
  const c = h.chat;
  const [messages, setMessages] = useState([]);
  const [createdAt, setCreatedAt] = useState(null);
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState(null);
  const [usage, setUsage] = useState(null);
  const endRef = useRef(null);

  useEffect(() => {
    if (!uid) return undefined;
    return listenHealthConversation({
      uid,
      scopeId,
      onChange: ({ messages: rows, createdAt: at }) => {
        setMessages(rows);
        setCreatedAt(at);
      },
      onError: (err) => setError(err.message),
    });
  }, [uid, scopeId]);

  useEffect(() => {
    endRef.current?.scrollIntoView({ block: "end" });
  }, [messages, sending]);

  const send = async () => {
    const content = text.trim();
    if (!content || sending) return;
    setSending(true);
    setError(null);

    const outgoing = [
      ...messages,
      { id: newId(), role: "user", content, createdAt: Date.now() },
    ];
    // Il messaggio si salva prima della risposta: se la chiamata fallisce, la
    // domanda resta scritta invece di sparire con l'errore.
    setMessages(outgoing);
    setText("");

    try {
      await saveHealthConversation({
        uid,
        kind,
        subjectId,
        scopeId,
        messages: outgoing,
        createdAt: createdAt || outgoing[0].createdAt,
      });

      const reply = await askAssistant({
        messages: outgoing,
        systemPrompt,
        familyId,
      });

      const complete = [
        ...outgoing,
        { id: newId(), role: "assistant", content: reply.reply, createdAt: Date.now() },
      ];
      setMessages(complete);
      setUsage({ usageToday: reply.usageToday, dailyLimit: reply.dailyLimit });
      await saveHealthConversation({
        uid,
        kind,
        subjectId,
        scopeId,
        messages: complete,
        createdAt: createdAt || outgoing[0].createdAt,
      });
    } catch (err) {
      setError(err.message);
    } finally {
      setSending(false);
    }
  };

  const clear = async () => {
    if (!window.confirm(c.confirmClear)) return;
    try {
      await clearHealthConversation({ uid, kind, subjectId, scopeId });
      setMessages([]);
      setUsage(null);
    } catch (err) {
      setError(err.message);
    }
  };

  return (
    <div className="pw-detail-overlay" onClick={onClose}>
      <aside className="pw-detail sa-chat" onClick={(e) => e.stopPropagation()}>
        <header>
          <h2>{title}</h2>
          <button onClick={onClose}>✕</button>
        </header>

        <p className="pw-hint">{c.disclaimer}</p>
        {error && <p className="error">{error}</p>}

        <div className="sa-chat-log">
          {messages.length === 0 && !sending && <p className="pw-hint">{c.empty}</p>}
          {messages.map((m) => (
            <div key={m.id} className={"sa-bubble " + m.role}>
              {/* Solo l'assistente scrive in Markdown; la domanda dell'utente
                  resta il testo che ha digitato, com'è anche su iOS. */}
              {m.role === "assistant" ? <MarkdownText text={m.content} /> : m.content}
            </div>
          ))}
          {sending && <div className="sa-bubble assistant pending">{c.thinking}</div>}
          <div ref={endRef} />
        </div>

        {usage && usage.dailyLimit > 0 && (
          <p className="sa-item-meta">{c.usage(usage.usageToday, usage.dailyLimit)}</p>
        )}

        <div className="sa-chat-input">
          <textarea
            value={text}
            placeholder={c.placeholder}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              // Invio manda, Maiusc+Invio va a capo: come nella chat di famiglia.
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                send();
              }
            }}
          />
          <button className="pw-btn-primary" disabled={sending || !text.trim()} onClick={send}>
            {c.send}
          </button>
        </div>

        {messages.length > 0 && (
          <button className="sa-chip" onClick={clear}>
            {c.clear}
          </button>
        )}
      </aside>
    </div>
  );
}
