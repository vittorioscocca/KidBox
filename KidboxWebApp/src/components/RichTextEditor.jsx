import { useEffect, useRef } from "react";
import { sanitizeNoteHtml } from "../services/noteHtml";
import "./RichTextEditor.css";

/**
 * Editor del corpo nota. Usa un contentEditable perché il formato salvato è
 * HTML: gli stessi tag prodotti da iOS/Android vengono qui resi nativamente,
 * senza conversioni che perderebbero formattazione.
 *
 * `document.execCommand` è deprecato ma resta l'unica API supportata ovunque
 * per la formattazione inline; l'alternativa sarebbe un editor completo, non
 * giustificato per grassetto/corsivo/liste.
 */
const ACTIONS = [
  { cmd: "bold", label: "B", title: "Grassetto", style: { fontWeight: 700 } },
  { cmd: "italic", label: "I", title: "Corsivo", style: { fontStyle: "italic" } },
  { cmd: "underline", label: "U", title: "Sottolineato", style: { textDecoration: "underline" } },
  { cmd: "strikeThrough", label: "S", title: "Barrato", style: { textDecoration: "line-through" } },
  { sep: true },
  { cmd: "insertUnorderedList", label: "•", title: "Elenco puntato" },
  { cmd: "insertOrderedList", label: "1.", title: "Elenco numerato" },
];

export default function RichTextEditor({ value, onChange, placeholder }) {
  const ref = useRef(null);
  const lastEmitted = useRef("");

  // Si riscrive il DOM solo quando il valore arriva da fuori (cambio nota o
  // aggiornamento remoto): farlo a ogni battuta sposterebbe il cursore a inizio
  // riga mentre si scrive.
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const incoming = sanitizeNoteHtml(value ?? "");
    if (incoming !== lastEmitted.current) {
      el.innerHTML = incoming;
      lastEmitted.current = incoming;
    }
  }, [value]);

  const emit = () => {
    const html = sanitizeNoteHtml(ref.current?.innerHTML ?? "");
    lastEmitted.current = html;
    onChange(html);
  };

  const run = (cmd) => {
    ref.current?.focus();
    document.execCommand(cmd, false, null);
    emit();
  };

  return (
    <div className="rte">
      <div className="rte-toolbar">
        {ACTIONS.map((a, i) =>
          a.sep ? (
            <span key={i} className="rte-sep" />
          ) : (
            <button
              key={a.cmd}
              type="button"
              className="rte-btn"
              title={a.title}
              style={a.style}
              // onMouseDown invece di onClick: il click sposterebbe il focus
              // fuori dall'editor perdendo la selezione da formattare.
              onMouseDown={(e) => {
                e.preventDefault();
                run(a.cmd);
              }}
            >
              {a.label}
            </button>
          )
        )}
      </div>

      <div
        ref={ref}
        className="rte-body"
        contentEditable
        suppressContentEditableWarning
        data-placeholder={placeholder}
        onInput={emit}
        onBlur={emit}
        // Incolla come testo semplice: l'HTML del sistema operativo porterebbe
        // stili e tag che i client nativi non sanno rendere.
        onPaste={(e) => {
          e.preventDefault();
          const text = e.clipboardData.getData("text/plain");
          document.execCommand("insertText", false, text);
        }}
      />
    </div>
  );
}
