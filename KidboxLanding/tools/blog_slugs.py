# -*- coding: utf-8 -*-
"""
Slug tradotti del blog: l'URL di un articolo in inglese, spagnolo e francese.

L'identità di un articolo resta lo slug italiano (`a["slug"]`, usato in
`related`, `tools`, nei link dei body e come chiave delle traduzioni): qui si
decide solo COME si chiama la pagina nelle altre lingue. Un articolo senza
voce per una lingua tiene lo slug italiano; le lingue non tradotte non
compaiono. Gli slug sono ASCII, brevi, con la parola chiave del titolo.

Chi cambia uno slug qui deve tenere il vecchio URL vivo: `build_redirects.py`
scrive in firebase.json un 301 da ogni URL precedente (`OLD`) a quello nuovo.
"""

CATEGORY_SLUGS = {
    "casa-e-faccende":          {"en": "home-and-chores",       "es": "casa-y-tareas",           "fr": "maison-et-taches"},
    "genitori-separati":        {"en": "co-parenting",          "es": "padres-separados",        "fr": "parents-separes"},
    "confronti":                {"en": "app-comparisons",       "es": "comparativas-de-apps",    "fr": "comparatifs-apps"},
    "organizzazione-familiare": {"en": "family-organisation",   "es": "organizacion-familiar",   "fr": "organisation-familiale"},
    "pasti-e-spesa":            {"en": "meals-and-groceries",   "es": "comidas-y-compra",        "fr": "repas-et-courses"},
    "produttivita-in-casa":     {"en": "productivity-at-home",  "es": "productividad-en-casa",   "fr": "productivite-a-la-maison"},
    "salute-e-documenti":       {"en": "health-and-documents",  "es": "salud-y-documentos",      "fr": "sante-et-papiers"},
    "viaggi-in-famiglia":       {"en": "family-travel",         "es": "viajes-en-familia",       "fr": "voyages-en-famille"},
    "animali-e-auto":           {"en": "pets-and-cars",         "es": "mascotas-y-coche",        "fr": "animaux-et-voiture"},
}

SLUGS = {
    # ── Casa e faccende ──────────────────────────────────────────────────
    "faccende-per-eta-bambini":            {"en": "age-appropriate-chores-for-kids",        "es": "tareas-del-hogar-segun-la-edad",          "fr": "taches-menageres-selon-l-age"},
    "dividere-le-faccende-in-coppia":      {"en": "splitting-chores-as-a-couple",           "es": "repartir-las-tareas-en-pareja",           "fr": "partager-les-taches-en-couple"},
    "scadenze-di-casa-bollette-garanzie":  {"en": "household-deadlines-bills-warranties"},
    "faccende-e-adhd":                     {"en": "chores-and-adhd",                        "es": "tareas-del-hogar-y-tdah",                 "fr": "taches-menageres-et-tdah"},
    "faccende-tra-adulti":                 {"en": "chores-between-adults",                  "es": "tareas-entre-adultos",                    "fr": "taches-entre-adultes"},
    "far-fare-le-faccende-ai-bambini":     {"en": "get-kids-to-do-chores",                  "es": "que-los-ninos-hagan-las-tareas",          "fr": "faire-participer-les-enfants-aux-taches"},
    "faccende-per-adolescenti":            {"en": "chores-for-teenagers",                   "es": "tareas-para-adolescentes",                "fr": "taches-pour-les-ados"},
    "piano-settimanale-delle-pulizie":     {"en": "weekly-cleaning-schedule",               "es": "plan-semanal-de-limpieza",                "fr": "planning-de-menage-hebdomadaire"},
    "quando-un-partner-fa-di-piu":         {"en": "when-one-partner-does-more-at-home",     "es": "cuando-uno-hace-mas-en-casa",             "fr": "quand-l-un-en-fait-plus-a-la-maison"},
    "tabella-delle-faccende-per-bambini":  {"en": "chore-chart-for-kids",                   "es": "cuadrante-de-tareas-para-ninos",          "fr": "tableau-des-taches-pour-enfants"},
    "rotazione-delle-faccende":            {"en": "chore-rotation",                         "es": "rotacion-de-tareas",                      "fr": "rotation-des-taches"},
    "manutenzione-caldaia-e-impianti":     {"en": "boiler-and-home-systems-maintenance"},
    "garanzie-degli-elettrodomestici":     {"en": "appliance-warranties"},
    "bollette-e-contratti-di-casa":        {"en": "household-bills-and-contracts"},
    "trasloco-in-famiglia-checklist":      {"en": "moving-house-with-children-checklist"},
    "tasse-e-assicurazione-della-casa":    {"en": "home-taxes-and-insurance-deadlines"},
    # ── Genitori separati ────────────────────────────────────────────────
    "calendario-genitori-separati":        {"en": "co-parenting-calendar",                  "es": "calendario-de-coparentalidad",            "fr": "calendrier-de-coparentalite"},
    "spese-dei-figli-genitori-separati":   {"en": "kids-expenses-separated-parents",        "es": "gastos-de-los-hijos-padres-separados",    "fr": "depenses-des-enfants-parents-separes"},
    "documenti-dei-figli-in-due-case":     {"en": "kids-documents-two-homes",               "es": "documentos-de-los-hijos-dos-casas",       "fr": "papiers-des-enfants-deux-maisons"},
    "famiglia-allargata-organizzazione":   {"en": "blended-family-organisation",            "es": "familias-reconstituidas-organizacion",    "fr": "famille-recomposee-organisation"},
    "calendario-famiglia-ricomposta":      {"en": "blended-family-calendar",                "es": "calendario-familia-reconstituida",        "fr": "calendrier-famille-recomposee"},
    "confini-nella-co-genitorialita":      {"en": "co-parenting-boundaries",                "es": "limites-en-la-coparentalidad",            "fr": "limites-dans-la-coparentalite"},
    "genitorialita-parallela":             {"en": "parallel-parenting",                     "es": "parentalidad-paralela",                   "fr": "parentalite-parallele"},
    "co-genitorialita-a-distanza":         {"en": "long-distance-co-parenting",             "es": "coparentalidad-a-distancia",              "fr": "coparentalite-a-distance"},
    "nuovo-partner-e-co-genitorialita":    {"en": "co-parenting-with-a-new-partner",        "es": "coparentalidad-con-nueva-pareja",         "fr": "coparentalite-avec-un-nouveau-conjoint"},
    "comunicazione-tra-genitori-separati": {"en": "talking-to-your-ex-about-the-kids",      "es": "hablar-con-tu-ex-sobre-los-hijos",        "fr": "parler-des-enfants-avec-son-ex"},
    "calendario-di-affido":                {"en": "shared-custody-schedules",               "es": "calendarios-de-custodia-compartida",      "fr": "calendriers-de-garde-alternee"},
    # ── Confronti ────────────────────────────────────────────────────────
    "app-per-genitori-separati-cosa-serve":        {"en": "co-parenting-apps-what-they-need",      "es": "apps-para-la-coparentalidad",             "fr": "applis-de-coparentalite"},
    "organizer-di-famiglia-vs-calendario-e-chat":  {"en": "family-organiser-vs-calendar-and-chat", "es": "organizador-familiar-vs-calendario-y-chat", "fr": "organiseur-familial-vs-calendrier-et-chat"},
    "app-di-famiglia-gratis-cosa-guardare":        {"en": "free-family-apps-what-to-check",        "es": "apps-familiares-gratis",                  "fr": "applis-familiales-gratuites"},
    "app-per-coppie-cosa-serve":                   {"en": "apps-for-couples",                      "es": "apps-para-parejas",                       "fr": "applis-pour-couples"},
    "app-tabella-faccende-cosa-guardare":          {"en": "chore-chart-apps"},
    "app-di-famiglia-iphone-android-web":          {"en": "family-app-iphone-android-web",         "es": "app-familiar-iphone-android-web",         "fr": "appli-familiale-iphone-android-web"},
    # ── Organizzazione familiare ─────────────────────────────────────────
    "documenti-di-famiglia-in-ordine":     {"en": "family-documents-in-order",              "es": "documentos-de-la-familia-en-orden",       "fr": "papiers-de-famille-en-ordre"},
    "storia-sanitaria-dei-figli":          {"en": "kids-health-history",                    "es": "historial-de-salud-de-los-hijos",         "fr": "dossier-de-sante-des-enfants"},
    "posizione-famiglia-senza-controllo":  {"en": "family-location-sharing-without-surveillance", "es": "compartir-ubicacion-en-familia",    "fr": "partager-sa-position-en-famille"},
    "orari-dopo-scuola-genitori-che-lavorano": {"en": "after-school-when-both-parents-work", "es": "despues-del-colegio-padres-que-trabajan", "fr": "apres-l-ecole-parents-qui-travaillent"},
    "primo-anno-da-neogenitori":           {"en": "first-year-as-new-parents",              "es": "primer-ano-padres-primerizos",            "fr": "premiere-annee-jeunes-parents"},
    "assistenza-a-un-familiare-turni":     {"en": "caring-for-an-elderly-parent-among-siblings", "es": "cuidar-a-un-padre-mayor-entre-hermanos", "fr": "s-occuper-d-un-parent-age-entre-freres-et-soeurs"},
    "rientro-a-scuola-organizzazione":     {"en": "back-to-school-checklist",               "es": "vuelta-al-cole-sin-caos",                 "fr": "rentree-sans-chaos"},
    "partner-non-usa-app-di-famiglia":     {"en": "partner-wont-use-family-app",            "es": "tu-pareja-no-usa-la-app-familiar",        "fr": "conjoint-n-utilise-pas-l-appli-familiale"},
    "impegni-sportivi-dei-figli":          {"en": "kids-sports-schedules",                  "es": "actividades-deportivas-de-los-hijos",     "fr": "activites-sportives-des-enfants"},
    "riunione-di-famiglia":                {"en": "weekly-family-meeting",                  "es": "reunion-familiar-semanal",                "fr": "reunion-de-famille-hebdomadaire"},
    "regali-di-natale-organizzazione":     {"en": "organising-christmas-presents",          "es": "organizar-los-regalos-de-navidad",        "fr": "organiser-les-cadeaux-de-noel"},
    "chat-di-famiglia-separata-da-whatsapp": {"en": "family-chat-separate-from-whatsapp",   "es": "chat-familiar-separado-de-whatsapp",      "fr": "chat-familial-separe-de-whatsapp"},
    "vocali-in-famiglia-trascritti":       {"en": "voice-notes-in-the-family"},
    "gruppi-whatsapp-della-classe":        {"en": "class-parents-whatsapp-group"},
    "chat-con-figli-adolescenti":          {"en": "family-chat-with-teenagers"},
    "condivisione-temporanea-della-posizione": {"en": "temporary-location-sharing"},
    "zone-di-arrivo-scuola-e-casa":        {"en": "arrival-zones-school-and-home"},
    "primo-tragitto-da-solo-del-figlio":   {"en": "childs-first-walk-to-school-alone"},
    "posizione-in-coppia-e-privacy":       {"en": "location-sharing-as-a-couple"},
    # ── Pasti e spesa ────────────────────────────────────────────────────
    "lista-della-spesa-condivisa":         {"en": "shared-grocery-list",                    "es": "lista-de-la-compra-compartida",           "fr": "liste-de-courses-partagee"},
    "menu-della-settimana-in-famiglia":    {"en": "family-weekly-menu",                     "es": "menu-semanal-en-familia",                 "fr": "menu-de-la-semaine-en-famille"},
    "spesa-con-alexa":                     {"en": "grocery-list-with-alexa"},
    "pasti-in-famiglia-con-budget":        {"en": "family-meals-on-a-budget",               "es": "comidas-en-familia-con-presupuesto",      "fr": "repas-en-famille-avec-un-budget"},
    "cena-di-natale-organizzazione":       {"en": "organising-christmas-dinner",            "es": "organizar-la-cena-de-navidad",            "fr": "organiser-le-repas-de-noel"},
    "cosa-si-mangia-stasera":              {"en": "whats-for-dinner-tonight",               "es": "que-hay-de-cena",                         "fr": "qu-est-ce-qu-on-mange-ce-soir"},
    "preparare-i-pasti-in-anticipo":       {"en": "meal-prep-two-hour-method",              "es": "cocinar-por-adelantado",                  "fr": "cuisiner-a-l-avance"},
    "bambini-difficili-a-tavola":          {"en": "picky-eaters-meal-planning",             "es": "ninos-que-comen-mal",                     "fr": "enfants-difficiles-a-table"},
    # ── Produttività in casa ─────────────────────────────────────────────
    "routine-della-sera-in-famiglia":      {"en": "family-evening-routine",                 "es": "rutina-de-la-noche-en-familia",           "fr": "routine-du-soir-en-famille"},
    "lista-condivisa-per-coppie":          {"en": "shared-to-do-list-for-couples",          "es": "lista-de-tareas-compartida-en-pareja",    "fr": "liste-de-taches-partagee-en-couple"},
    "promemoria-che-funzionano":           {"en": "reminders-that-work",                    "es": "recordatorios-que-funcionan",             "fr": "rappels-qui-fonctionnent"},
    "carico-mentale-dei-genitori":         {"en": "mental-load-of-parents",                 "es": "carga-mental-de-los-padres",              "fr": "charge-mentale-des-parents"},
    "lavorare-a-blocchi-con-i-figli":      {"en": "time-blocking-with-kids-at-home",        "es": "trabajar-por-bloques-con-ninos-en-casa",  "fr": "travailler-par-blocs-avec-des-enfants"},
    "routine-del-mattino-in-famiglia":     {"en": "family-morning-routine",                 "es": "rutina-de-la-manana-en-familia",          "fr": "routine-du-matin-en-famille"},
    "budget-di-casa-spese-condivise":      {"en": "household-budget-shared-expenses",       "es": "presupuesto-de-casa-en-pareja",           "fr": "budget-du-foyer-a-deux"},
    "riordino-della-domenica":             {"en": "sunday-reset",                           "es": "reseteo-del-domingo",                     "fr": "reset-du-dimanche"},
    "tempo-davanti-agli-schermi-in-famiglia": {"en": "screen-time-in-the-family",           "es": "pantallas-en-familia",                    "fr": "ecrans-en-famille"},
    # ── Salute e documenti ───────────────────────────────────────────────
    "libretto-vaccinale-dei-figli":        {"en": "childrens-vaccination-record"},
    "cartella-clinica-di-famiglia":        {"en": "family-health-record"},
    "scadenze-documenti-di-identita":      {"en": "childrens-id-and-passport-expiry"},
    "dati-sanitari-cifrati":               {"en": "encrypted-medical-documents"},
    "farmaci-e-terapie-dei-figli":         {"en": "childrens-medicines-who-gives-them"},
    "figlio-malato-organizzarsi-tra-genitori": {"en": "child-is-ill-and-both-parents-work"},
    "dati-di-salute-dal-telefono":         {"en": "health-data-from-your-phone"},
    "piano-fitness-in-famiglia":           {"en": "exercising-when-you-have-kids"},
    "spese-mediche-di-famiglia":           {"en": "family-medical-expenses"},
    "password-di-famiglia-condivise":      {"en": "family-passwords"},
    "quanto-tempo-conservare-i-documenti": {"en": "how-long-to-keep-family-documents"},
    "digitalizzare-i-documenti-di-casa":   {"en": "digitising-household-documents"},
    "wallet-di-famiglia-carte-e-biglietti": {"en": "family-wallet-cards-and-tickets"},
    "fatture-e-referti-letti-dall-ai":     {"en": "ai-reads-invoices-and-medical-reports"},
    # ── Viaggi in famiglia ───────────────────────────────────────────────
    "itinerario-viaggio-con-bambini":      {"en": "trip-itinerary-with-children"},
    "valigia-e-documenti-viaggio-con-bambini": {"en": "travelling-with-children-packing-checklist"},
    "spese-di-viaggio-in-famiglia":        {"en": "family-holiday-budget"},
    "viaggio-in-auto-con-bambini":         {"en": "road-trips-with-children"},
    "volare-con-bambini":                  {"en": "flying-with-children"},
    "viaggiare-con-farmaci-e-allergie":    {"en": "travelling-with-allergies-or-medicine"},
    "vacanze-con-altre-famiglie":          {"en": "holiday-with-grandparents-or-another-family"},
    "foto-del-viaggio-album-condiviso":    {"en": "holiday-photos-shared-family-album"},
    "weekend-fuori-porta-con-bambini":     {"en": "weekend-away-with-children"},
    # ── Animali e auto ───────────────────────────────────────────────────
    "libretto-del-cane-e-del-gatto":       {"en": "dog-and-cat-health-record"},
    "animale-in-famiglia-chi-se-ne-occupa": {"en": "sharing-pet-care-in-the-family"},
    "scadenze-auto-bollo-assicurazione-revisione": {"en": "family-car-deadlines-tax-insurance-inspection"},
    "manutenzione-auto-storico-interventi": {"en": "family-car-maintenance-history"},
    "arrivo-di-un-cane-o-un-gatto":        {"en": "new-dog-or-cat-first-weeks-checklist"},
    "quanto-costa-un-animale-domestico":   {"en": "what-a-dog-or-cat-really-costs"},
    "animale-e-vacanze-pensione-pet-sitter": {"en": "holiday-without-the-dog-or-cat"},
    "animale-anziano-cure-e-controlli":    {"en": "when-your-dog-or-cat-gets-old"},
    "bambini-e-animali-in-casa":           {"en": "children-and-pets-at-home"},
    "quanto-costa-l-auto-di-famiglia":     {"en": "what-the-family-car-really-costs"},
    "due-auto-in-famiglia":                {"en": "two-cars-two-parents"},
    "figlio-neopatentato-in-famiglia":     {"en": "newly-licensed-teen-driver"},
    "incidente-o-guasto-cosa-fare":        {"en": "accident-or-breakdown-what-to-do"},
    "vendere-o-cambiare-l-auto":           {"en": "selling-or-replacing-the-family-car"},
}

# URL precedenti di ogni pagina, per i 301: {lingua: {slug attuale: [slug vecchi]}}.
# Fino al 21/09/2026 le traduzioni usavano lo slug italiano: `build_redirects.py`
# lo aggiunge da solo per ogni voce di SLUGS e CATEGORY_SLUGS. Qui vanno solo
# gli slug cambiati DOPO (es. una seconda rinomina), per non perdere il vecchio URL.
OLD = {"en": {}, "es": {}, "fr": {}}


def article_slug(article, lang):
    """Slug dell'articolo nella lingua: quello tradotto se c'è, altrimenti l'italiano."""
    return SLUGS.get(article["slug"], {}).get(lang, article["slug"])


def category_slug(cslug, lang):
    return CATEGORY_SLUGS.get(cslug, {}).get(lang, cslug)


def check(articles, categories):
    """Slug sconosciuti, mancanti per una lingua tradotta, o doppi nella stessa lingua."""
    by_slug = {a["slug"]: a for a in articles}
    for slug in SLUGS:
        if slug not in by_slug:
            raise SystemExit(f"blog_slugs: articolo sconosciuto {slug}")
    for slug, a in by_slug.items():
        for lang in ("en", "es", "fr"):
            if lang in a and lang not in SLUGS.get(slug, {}):
                raise SystemExit(f"blog_slugs: manca lo slug {lang} di {slug}")
    for cslug in categories:
        if cslug not in CATEGORY_SLUGS:
            raise SystemExit(f"blog_slugs: manca la categoria {cslug}")
    for lang in ("it", "en", "es", "fr"):
        seen = {}
        for a in articles:
            if lang not in a:
                continue
            s = article_slug(a, lang)
            if s in seen:
                raise SystemExit(f"blog_slugs [{lang}]: slug doppio {s} ({seen[s]} e {a['slug']})")
            if s in categories or s in {category_slug(c, lang) for c in categories}:
                raise SystemExit(f"blog_slugs [{lang}]: {s} è anche una categoria")
            seen[s] = a["slug"]
