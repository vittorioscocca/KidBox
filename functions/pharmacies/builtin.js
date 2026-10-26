// Fonti verificate a mano: sono regole come quelle generate dall'AI, ma scritte
// e provate da noi sulla pagina ufficiale. Il pilota del 26/10/2026 le ha
// trovate leggibili e senza divieti nel robots.txt; i termini d'uso di
// Federfarma vanno comunque letti prima di allargare la copertura.
//
// `coverage`: «region» = l'elenco copre tutta la regione e un comune senza
// turni oggi è un caso normale; «listed» = copre solo i comuni che compaiono
// nella pagina, e un comune assente vuol dire «fonte non adatta».

const BUILTIN_SOURCES = [
  {
    key: "lombardia",
    label: "Federfarma Lombardia",
    url: "https://www.farmacia-aperta.eu/ajax/farmacie",
    pageUrl: "https://www.farmacia-aperta.eu",
    countryCode: "IT",
    regionMatch: /lombard/,
    coverage: "region",
    refreshHours: 3,
    rule: {
      v: 1,
      type: "json",
      itemsPath: "farmacie",
      where: {di_turno: 1},
      dateField: "giorno",
      fields: {
        name: "ragione_sociale", address: "indirizzo", comune: "comune",
        phone: "telefono", lat: "lat", lng: "lng",
      },
    },
  },
  {
    key: "torino",
    label: "Federfarma Torino",
    url: "https://www.federfarmatorino.it/farmacie/farmacie-di-turno/",
    pageUrl: "https://www.federfarmatorino.it/farmacie/farmacie-di-turno/",
    countryCode: "IT",
    regionMatch: /piemonte/,
    provinceMatch: /torino|turin/,
    coverage: "listed",
    refreshHours: 12,
    rule: {
      v: 1,
      type: "html",
      dayContainerSelector: ".tf-day",
      dayHeaderSelector: ".tf-day-header",
      itemSelector: ".tf-pharmacy",
      fields: {name: ":self"},
      detailSelector: ".tf-detail",
      detailSeparator: " — ",
      detailFields: ["comune", "address", "phone"],
    },
  },
];

module.exports = {BUILTIN_SOURCES};
