/**
 * Categorie di spesa: porting di KBExpenseCategory.defaultCategories (iOS).
 *
 * Non vivono su Firestore — ogni client le genera in locale con un **ID
 * deterministico** `expcat-{familyId}-{slug}`. È quell'ID che la spesa salva in
 * `categoryId`, ed è il motivo per cui slug, nome e colore devono restare
 * identici fra le piattaforme: cambiarne uno spezzerebbe l'abbinamento.
 *
 * Le icone su iOS sono SF Symbols, non disponibili sul web: qui si usa l'emoji
 * più vicina, mentre colori e nomi restano quelli originali.
 */
export const EXPENSE_CATEGORIES = [
  { slug: "spesa", name: "Spesa", icon: "🛒", color: "#4CAF50" },
  { slug: "casa", name: "Casa", icon: "🏠", color: "#2196F3" },
  { slug: "trasporti", name: "Trasporti", icon: "🚌", color: "#FF9800" },
  { slug: "automobile", name: "Automobile", icon: "⛽️", color: "#D32F2F" },
  { slug: "salute", name: "Salute", icon: "❤️", color: "#E91E63" },
  { slug: "istruzione", name: "Istruzione", icon: "📚", color: "#9C27B0" },
  { slug: "sport", name: "Sport", icon: "🏃", color: "#00BCD4" },
  { slug: "abbigliamento", name: "Abbigliamento", icon: "👕", color: "#FF5722" },
  { slug: "ristoranti", name: "Ristoranti", icon: "🍴", color: "#795548" },
  { slug: "intrattenimento", name: "Intrattenimento", icon: "🎮", color: "#607D8B" },
  { slug: "viaggi", name: "Viaggi", icon: "✈️", color: "#03A9F4" },
  { slug: "elettronica", name: "Elettronica", icon: "💻", color: "#3F51B5" },
  { slug: "animali", name: "Animali domestici", icon: "🐾", color: "#8BC34A" },
  { slug: "altro", name: "Altro", icon: "⋯", color: "#9E9E9E" },
];

export function categoryId(familyId, slug) {
  return `expcat-${familyId}-${slug}`;
}

/** Risale alla categoria partendo dall'ID salvato sulla spesa. */
export function categoryFromId(familyId, id) {
  if (!id) return null;
  const prefix = `expcat-${familyId}-`;
  if (!id.startsWith(prefix)) return null;
  const slug = id.slice(prefix.length);
  return EXPENSE_CATEGORIES.find((c) => c.slug === slug) ?? null;
}

/** Periodi del selettore, come ExpensePeriod su iOS. */
export const PERIODS = ["oneMonth", "threeMonths", "sixMonths", "oneYear", "custom"];

export function periodRange(period, today = new Date()) {
  const end = new Date(today);
  end.setHours(23, 59, 59, 999);
  const start = new Date(today);
  start.setHours(0, 0, 0, 0);

  switch (period) {
    case "oneMonth":
      start.setMonth(start.getMonth() - 1);
      break;
    case "threeMonths":
      start.setMonth(start.getMonth() - 3);
      break;
    case "sixMonths":
      start.setMonth(start.getMonth() - 6);
      break;
    case "oneYear":
      start.setFullYear(start.getFullYear() - 1);
      break;
    default:
      break;
  }
  return { start, end };
}

export function formatAmount(value, locale) {
  return new Intl.NumberFormat(locale === "en" ? "en-US" : "it-IT", {
    style: "currency",
    currency: "EUR",
  }).format(value ?? 0);
}
