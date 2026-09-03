/**
 * Copertine dei viaggi: la foto della destinazione da Wikipedia.
 *
 * Porta la stessa disambiguazione geografica di `TravelPlaceInfoService` su
 * iOS. Non è un dettaglio: la ricerca diretta per «Margherita di Savoia»
 * restituisce la regina, e la copertina del viaggio finirebbe per mostrare il
 * suo ritratto invece del paese. Si tengono solo gli articoli che hanno
 * coordinate geografiche — quelle ce l'ha un comune, non una persona.
 *
 * Senza foto la card resta col suo gradiente: una copertina sbagliata è
 * peggio di nessuna copertina.
 */

const cache = new Map();

const api = (language, params) =>
  `https://${language}.wikipedia.org/w/api.php?${new URLSearchParams({
    format: "json",
    formatversion: "2",
    // Wikipedia risponde con CORS solo se l'origine è dichiarata.
    origin: "*",
    ...params,
  })}`;

async function getJson(url) {
  const res = await fetch(url);
  if (!res.ok) return null;
  return res.json();
}

/** Primo articolo rilevante che sia un luogo e non una disambigua. */
async function geoDisambiguatedTitle(place, language) {
  const json = await getJson(
    api(language, {
      action: "query",
      generator: "search",
      gsrsearch: place,
      gsrlimit: "5",
      prop: "coordinates|pageprops",
    })
  );
  const pages = json?.query?.pages;
  if (!Array.isArray(pages)) return null;

  // I risultati arrivano senza ordine garantito: `index` conserva il ranking.
  return (
    [...pages]
      .sort((a, b) => (a.index ?? Infinity) - (b.index ?? Infinity))
      .find((page) => !page.pageprops?.disambiguation && page.coordinates && page.title)?.title ??
    null
  );
}

async function summaryImage(title, language) {
  const encoded = encodeURIComponent(title.replace(/ /g, "_"));
  const json = await getJson(
    `https://${language}.wikipedia.org/api/rest_v1/page/summary/${encoded}`
  );
  return json?.originalimage?.source || json?.thumbnail?.source || null;
}

/** URL della foto per la destinazione, `null` se non se ne trova una sicura. */
export async function placeImageURL(destination) {
  const key = destination.trim().toLowerCase();
  if (!key) return null;
  if (cache.has(key)) return cache.get(key);

  let url = null;
  try {
    for (const language of ["it", "en"]) {
      const title = await geoDisambiguatedTitle(destination, language);
      if (!title) continue;
      url = await summaryImage(title, language);
      if (url) break;
    }
  } catch {
    url = null;
  }

  cache.set(key, url);
  return url;
}
