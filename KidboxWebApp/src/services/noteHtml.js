/**
 * Il corpo delle note è HTML: i client nativi lo producono da NSAttributedString /
 * Spanned e lo ripuliscono con NoteHtmlSanitizer prima di salvarlo.
 *
 * Sul web quell'HTML finisce nel DOM di un contentEditable, quindi qui la
 * sanitizzazione non è cosmetica ma necessaria: senza allowlist, una nota che
 * contenesse `<script>` o un `onerror=` eseguirebbe codice nella sessione di chi
 * la apre. Si tiene solo ciò che serve alla formattazione supportata dalle app.
 */
const ALLOWED_TAGS = new Set([
  "P", "BR", "DIV", "SPAN",
  "B", "STRONG", "I", "EM", "U", "S", "STRIKE", "DEL",
  "UL", "OL", "LI",
  "H1", "H2", "H3", "H4",
  "BLOCKQUOTE", "PRE", "CODE",
]);

// `style` è permesso ma filtrato: i nativi lo usano per grassetto/corsivo inline.
const ALLOWED_STYLE_PROPS = new Set([
  "font-weight",
  "font-style",
  "text-decoration",
  "text-decoration-line",
]);

function cleanStyle(value) {
  return value
    .split(";")
    .map((decl) => decl.trim())
    .filter((decl) => {
      const prop = decl.split(":")[0]?.trim().toLowerCase();
      return prop && ALLOWED_STYLE_PROPS.has(prop);
    })
    .join("; ");
}

function scrub(node) {
  [...node.children].forEach((child) => {
    if (!ALLOWED_TAGS.has(child.tagName)) {
      // Tag non ammesso: se ne conserva il testo, si butta l'elemento.
      const text = document.createTextNode(child.textContent ?? "");
      child.replaceWith(text);
      return;
    }
    // Via ogni attributo tranne uno `style` ripulito: qui vivono gli handler
    // inline (onclick, onerror, …) e gli href javascript:.
    [...child.attributes].forEach((attr) => {
      if (attr.name.toLowerCase() === "style") {
        const safe = cleanStyle(attr.value);
        if (safe) child.setAttribute("style", safe);
        else child.removeAttribute("style");
      } else {
        child.removeAttribute(attr.name);
      }
    });
    scrub(child);
  });
}

/** HTML pronto da inserire nel DOM. */
export function sanitizeNoteHtml(html) {
  if (!html) return "";
  const parsed = new DOMParser().parseFromString(html, "text/html");
  // `parseFromString` non esegue script né carica risorse: il filtro sotto
  // rimuove comunque tutto ciò che non è nell'allowlist.
  parsed.body.querySelectorAll("script, style, head, meta, link, title, iframe, object, embed")
    .forEach((el) => el.remove());
  scrub(parsed.body);
  return parsed.body.innerHTML.trim();
}

/** Testo semplice per anteprime e ricerca (equivalente di NoteHtmlSanitizer.plainText). */
export function noteHtmlToText(html) {
  if (!html) return "";
  if (!/<[a-z][\s\S]*>/i.test(html)) return html; // già testo semplice
  const parsed = new DOMParser().parseFromString(html, "text/html");
  parsed.body.querySelectorAll("script, style").forEach((el) => el.remove());
  return (parsed.body.textContent ?? "").replace(/\s+/g, " ").trim();
}

/** Una nota è vuota se, tolti i tag, non resta nulla. */
export function isEmptyNoteHtml(html) {
  return noteHtmlToText(html).length === 0;
}
