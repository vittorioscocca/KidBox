/**
 * Markdown delle risposte AI, reso a blocchi — porting di
 * `AIClaudeMarkdownText` (`AIChatBubbleView.swift`).
 *
 * Il modello risponde in Markdown e la bolla lo stampava come testo semplice:
 * a video finivano i cancelletti e gli asterischi. Qui si riconoscono gli
 * stessi blocchi del telefono — titoli, paragrafi, elenchi puntati e numerati,
 * blocchi di codice — con grassetto, corsivo, codice in linea e link dentro la
 * riga.
 *
 * Niente `dangerouslySetInnerHTML` e niente libreria: il testo arriva da un
 * modello e viene costruito come nodi React, quindi non c'è modo che una
 * risposta finisca interpretata come HTML.
 *
 * Una differenza voluta rispetto a iOS: qui si riconosce anche il titolo di
 * primo livello (`# `), che sul telefono non è previsto e resta a video col
 * cancelletto.
 */
import "./MarkdownText.css";

const ORDERED = /^(\d+)\.\s+/;
const BULLET = /^[-*]\s+/;
const HEADING = /^(#{1,3})\s+/;

/** Righe → blocchi, con lo stesso ordine di riconoscimento del telefono. */
function parseBlocks(source) {
  const lines = (source || "").replace(/\r\n/g, "\n").split("\n");
  const blocks = [];
  let i = 0;

  while (i < lines.length) {
    const trimmed = lines[i].trim();

    if (trimmed.startsWith("```")) {
      i += 1;
      const code = [];
      while (i < lines.length && !lines[i].trim().startsWith("```")) {
        code.push(lines[i]);
        i += 1;
      }
      i += 1; // la riga di chiusura
      blocks.push({ type: "code", text: code.join("\n") });
      continue;
    }

    const heading = HEADING.exec(trimmed);
    if (heading) {
      blocks.push({
        type: "heading",
        level: heading[1].length,
        text: trimmed.slice(heading[0].length),
      });
      i += 1;
      continue;
    }

    if (BULLET.test(trimmed) || ORDERED.test(trimmed)) {
      const ordered = ORDERED.test(trimmed);
      const items = [];
      while (i < lines.length) {
        const t = lines[i].trim();
        const match = ordered ? ORDERED.exec(t) : BULLET.exec(t);
        if (!match) break;
        items.push(t.slice(match[0].length));
        i += 1;
      }
      blocks.push({ type: "list", ordered, items });
      continue;
    }

    if (!trimmed) {
      i += 1;
      continue;
    }

    // Paragrafo: va avanti finché non comincia un altro blocco.
    const paragraph = [lines[i]];
    i += 1;
    while (i < lines.length) {
      const t = lines[i].trim();
      if (!t || HEADING.test(t) || t.startsWith("```") || BULLET.test(t) || ORDERED.test(t)) break;
      paragraph.push(lines[i]);
      i += 1;
    }
    blocks.push({ type: "paragraph", text: paragraph.join("\n").trim() });
  }

  return blocks;
}

/** `**grassetto**`, `*corsivo*`, `` `codice` ``, `[testo](url)`. */
const INLINE = /(\*\*[^*]+\*\*|__[^_]+__|\*[^*\n]+\*|_[^_\n]+_|`[^`]+`|\[[^\]]+\]\([^)\s]+\))/g;

function renderInline(text) {
  const out = [];
  let last = 0;
  let match;
  INLINE.lastIndex = 0;
  while ((match = INLINE.exec(text)) !== null) {
    if (match.index > last) out.push(text.slice(last, match.index));
    const token = match[0];
    const key = `${match.index}-${token.length}`;
    if (token.startsWith("**") || token.startsWith("__")) {
      out.push(<strong key={key}>{token.slice(2, -2)}</strong>);
    } else if (token.startsWith("`")) {
      out.push(<code key={key}>{token.slice(1, -1)}</code>);
    } else if (token.startsWith("[")) {
      const label = token.slice(1, token.indexOf("]"));
      const href = token.slice(token.indexOf("](") + 2, -1);
      // Solo http(s): un `javascript:` in una risposta del modello non deve
      // diventare un link cliccabile. Quello che si scarta resta a video com'era
      // scritto — riscriverlo col solo testo perderebbe pezzi, per esempio le
      // parentesi dentro l'indirizzo.
      out.push(
        /^https?:\/\//i.test(href) ? (
          <a key={key} href={href} target="_blank" rel="noreferrer noopener">
            {label}
          </a>
        ) : (
          token
        )
      );
    } else {
      out.push(<em key={key}>{token.slice(1, -1)}</em>);
    }
    last = match.index + token.length;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

export default function MarkdownText({ text }) {
  const blocks = parseBlocks(text);
  return (
    <div className="md">
      {blocks.map((block, i) => {
        switch (block.type) {
          case "heading": {
            const Tag = `h${Math.min(block.level + 2, 6)}`;
            return (
              <Tag key={i} className={`md-h md-h${block.level}`}>
                {renderInline(block.text)}
              </Tag>
            );
          }
          case "list":
            return block.ordered ? (
              <ol key={i} className="md-list">
                {block.items.map((item, j) => (
                  <li key={j}>{renderInline(item)}</li>
                ))}
              </ol>
            ) : (
              <ul key={i} className="md-list">
                {block.items.map((item, j) => (
                  <li key={j}>{renderInline(item)}</li>
                ))}
              </ul>
            );
          case "code":
            return (
              <pre key={i} className="md-code">
                <code>{block.text}</code>
              </pre>
            );
          default:
            return (
              <p key={i} className="md-p">
                {renderInline(block.text)}
              </p>
            );
        }
      })}
    </div>
  );
}
