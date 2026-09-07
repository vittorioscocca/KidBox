/**
 * Lettura di una vCard (.vcf) lato client.
 *
 * Sul Mac non esiste l'equivalente web di `CNContactPickerViewController`: la
 * Contact Picker API (`navigator.contacts`) c'è solo su Chrome Android, e
 * nessuno schema URL restituisce un contatto alla pagina. Il ponte con
 * Contatti.app è quindi la vCard, che l'app produce in tre modi — trascinando
 * la scheda, esportandola, o copiandola con ⌘C — e che qui riportiamo ai campi
 * del form.
 *
 * Il parser copre quel che quei tre modi generano davvero: vCard 2.1/3.0/4.0,
 * righe piegate, gruppi (`item1.TEL`), e il quoted-printable degli export
 * vecchi. Il resto delle proprietà lo ignoriamo di proposito.
 */

/** Righe logiche: la piegatura RFC 6350 continua con spazio o tab. */
function unfold(text) {
  const raw = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
  const lines = [];
  for (const line of raw) {
    if (/^[ \t]/.test(line) && lines.length) lines[lines.length - 1] += line.slice(1);
    else lines.push(line);
  }
  return lines;
}

function decodeQuotedPrintable(value) {
  const bytes = [];
  for (let i = 0; i < value.length; i += 1) {
    if (value[i] === "=" && /^[0-9A-Fa-f]{2}$/.test(value.slice(i + 1, i + 3))) {
      bytes.push(parseInt(value.slice(i + 1, i + 3), 16));
      i += 2;
    } else {
      bytes.push(value.charCodeAt(i));
    }
  }
  try {
    return new TextDecoder("utf-8").decode(new Uint8Array(bytes));
  } catch {
    return value;
  }
}

/** `\,` `\;` `\\` `\n` come da specifica: il valore arriva già escapato. */
function unescapeValue(value) {
  return value.replace(/\\([,;\\nN])/g, (_, ch) => (ch === "n" || ch === "N" ? "\n" : ch));
}

/** `item1.TEL;TYPE=CELL:+39…` → nome, parametri, valore. */
function parseLine(line) {
  const colon = line.indexOf(":");
  if (colon < 0) return null;
  const head = line.slice(0, colon).split(";");
  const name = head[0].replace(/^[^.]+\./, "").toUpperCase();
  const params = {};
  for (const part of head.slice(1)) {
    const eq = part.indexOf("=");
    const key = (eq < 0 ? part : part.slice(0, eq)).toUpperCase();
    const val = (eq < 0 ? part : part.slice(eq + 1)).replace(/"/g, "").toUpperCase();
    params[key] = params[key] ? `${params[key]},${val}` : val;
  }
  return { name, params, value: line.slice(colon + 1) };
}

function typesOf(params) {
  return `${params.TYPE || ""},${Object.keys(params).join(",")}`;
}

/** Cellulare e numeri preferiti per primi: è quello che si vuole condividere. */
function rank(params) {
  const t = typesOf(params);
  if (t.includes("PREF")) return 0;
  if (t.includes("CELL") || t.includes("MOBILE") || t.includes("IPHONE")) return 1;
  return 2;
}

/** Etichetta leggibile del numero/indirizzo, come fa iOS. */
function labelOf(params) {
  const t = typesOf(params);
  if (t.includes("CELL") || t.includes("MOBILE") || t.includes("IPHONE")) return "mobile";
  if (t.includes("WORK")) return "work";
  if (t.includes("HOME")) return "home";
  return "";
}

/**
 * Primo contatto di una vCard (le multi-scheda si fermano al primo BEGIN).
 * Torna `null` se il testo non è una vCard.
 */
export function parseVCard(text) {
  if (!text || !/BEGIN:VCARD/i.test(text)) return null;

  const lines = unfold(text);
  const phones = [];
  const emails = [];
  let given = "";
  let family = "";
  let fullName = "";
  let started = false;

  for (let i = 0; i < lines.length; i += 1) {
    let line = lines[i];
    if (/^BEGIN:VCARD/i.test(line)) {
      if (started) break; // seconda scheda: la ignoriamo
      started = true;
      continue;
    }
    if (/^END:VCARD/i.test(line)) break;
    if (!started) continue;

    const parsed = parseLine(line);
    if (!parsed) continue;
    let { name, params, value } = parsed;

    if ((params.ENCODING || "").includes("QUOTED-PRINTABLE")) {
      // Il quoted-printable ha una sua continuazione: riga che finisce con «=».
      while (value.endsWith("=") && i + 1 < lines.length) {
        i += 1;
        value = value.slice(0, -1) + lines[i];
      }
      value = decodeQuotedPrintable(value);
    }

    switch (name) {
      case "N": {
        const parts = value.split(";").map(unescapeValue);
        family = parts[0] || "";
        given = parts[1] || "";
        break;
      }
      case "FN":
        fullName = unescapeValue(value);
        break;
      case "TEL":
        if (value.trim()) phones.push({ label: labelOf(params), value: value.trim(), rank: rank(params) });
        break;
      case "EMAIL":
        if (value.trim()) emails.push({ label: labelOf(params), value: value.trim(), rank: rank(params) });
        break;
      default:
        break;
    }
  }

  if (!started) return null;

  if (!given && !family && fullName) {
    // Senza `N` si spezza `FN`: primo token nome, il resto cognome.
    const space = fullName.indexOf(" ");
    if (space < 0) given = fullName;
    else {
      given = fullName.slice(0, space);
      family = fullName.slice(space + 1);
    }
  }

  const sorted = (list) => list.sort((a, b) => a.rank - b.rank).map(({ label, value }) => ({ label, value }));
  const result = { givenName: given, familyName: family, phones: sorted(phones), emails: sorted(emails) };
  if (!result.givenName && !result.familyName && !result.phones.length && !result.emails.length) return null;
  return result;
}

/** Contatto della vCard nella forma del form della chat. */
export function vCardToDraft(text) {
  const contact = parseVCard(text);
  if (!contact) return null;
  return {
    givenName: contact.givenName,
    familyName: contact.familyName,
    phone: contact.phones[0]?.value || "",
    email: contact.emails[0]?.value || "",
  };
}

/** Il file trascinato/incollato è una vCard. */
export function findVCardFile(dataTransfer) {
  return Array.from(dataTransfer?.files || []).find((f) => /\.vcf$/i.test(f.name) || /vcard/i.test(f.type)) || null;
}

/**
 * Contatto dal testo del trasferimento, senza `await`: l'incolla deve decidere
 * se bloccare l'inserimento predefinito mentre l'evento è ancora in corso.
 */
export function draftFromTransferText(dataTransfer) {
  if (!dataTransfer?.getData) return null;
  for (const type of ["text/vcard", "text/x-vcard", "text/directory", "text/plain"]) {
    let text = "";
    try {
      text = dataTransfer.getData(type);
    } catch {
      text = "";
    }
    const draft = text ? vCardToDraft(text) : null;
    if (draft) return draft;
  }
  return null;
}

/** Estrae la vCard da un drop: prima i file, poi il testo. */
export async function draftFromDataTransfer(dataTransfer) {
  if (!dataTransfer) return null;
  const file = findVCardFile(dataTransfer);
  if (file) return vCardToDraft(await file.text());
  return draftFromTransferText(dataTransfer);
}
