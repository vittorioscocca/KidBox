---
name: landing-blog
description: Scrivere o modificare articoli del blog della landing KidBox, rigenerare pagine, footer e sitemap, e pubblicare. Usare quando l'utente chiede un articolo nuovo, una categoria, di correggere un testo del blog, o quando si tocca una pagina statica della landing che entra in sitemap e footer.
---

Il blog sta su `kidboxapp.com`, **116 pagine per lingua** in IT ed EN più le
traduzioni ES/FR, in 9 categorie. La struttura è ricalcata su un concorrente
(gethomsy.com) **solo nell'impianto**: i testi sono originali, scritti attorno
alle funzioni vere di KidBox. **I testi altrui non si copiano, nemmeno
cambiando i nomi.** L'elenco dei titoli da cui pescare è esaurito: quello che
resta lì sono varianti di temi già scritti, confronti nominali, coinquilini e
ricette — scartati di proposito.

## Dove vivono i pezzi

| Cosa | Dove |
|---|---|
| Categorie + articoli «Casa e faccende» + assemblaggio | `KidboxLanding/tools/blog_data.py` |
| Le altre categorie | `tools/blog_<categoria>.py` |
| Traduzioni ES/FR | `tools/blog_es_<n>.py`, `blog_fr_<n>.py`, unite da `tools/blog_i18n.py` |
| Slug EN/ES/FR di articoli e categorie | `tools/blog_slugs.py` (obbligatorio per ogni lingua tradotta: il generatore si ferma se manca) |
| Generatore | `scripts/build_blog.py` → `public/blog/`, `public/en/blog/`, `es/blog/`, `fr/blog/` |
| Footer-mappa, sitemap, 301 | `scripts/build_footer.py`, `scripts/build_sitemap.py`, `scripts/build_redirects.py` → blocco `redirects` di `firebase.json` |

`blog_i18n.py` raccoglie da solo tutti i `blog_<lingua>_<n>.py`: per un lotto
nuovo basta creare il file.

## Un articolo nuovo

1. Aggiungi il dizionario nel modulo della categoria, **IT ed EN insieme**, con
   `related` e `tools` che puntino a slug **esistenti** (il generatore controlla
   slug duplicati e link rotti, ma solo se li lanci).
   Lo slug italiano è l'**identità** dell'articolo: `related`, `tools`, le chiavi
   delle traduzioni e i link nei body (`/en/blog/<slug-italiano>`) usano sempre
   quello, in ogni lingua. L'URL della pagina EN/ES/FR è invece lo slug tradotto
   in `tools/blog_slugs.py`: aggiungilo lì (ASCII, breve, la parola chiave del
   titolo), il generatore riscrive i link da sé. Dal 21/09/2026 le traduzioni
   non usano più lo slug italiano: quei vecchi URL vivono come 301 generati in
   `firebase.json`. **Se rinomini uno slug già online**, metti il vecchio in
   `blog_slugs.OLD` o la pagina indicizzata muore.
2. `python3 scripts/build_blog.py` dalla cartella `KidboxLanding/`.
3. `firebase deploy --only hosting:landing --project kidbox-42cd7`, poi commit
   per path.

Se tocchi `index.html` / `index-en.html`, **rilancia entrambi i generatori**
(`build_tools.py` e `build_blog.py`): nav e footer li riscrivono loro.
Per una pagina statica nuova: aggiungila a mano in `STATIC` di
`build_sitemap.py` (base italiana, le varianti `-en/-es/-fr` le trova da sola) e
in `STATIC_BASES` di `tools/site_langs.py`. `lastmod` viene dal **git log dei
sorgenti**, non dall'mtime.

## Le regole editoriali (da `FEATURES.md`, non negoziabili)

- Niente «faccende» come modulo: sono to-do assegnabili più le scadenze di Casa.
- Alexa **solo in italiano**; Piano Alimentare, assistente AI e viaggi sono a
  pagamento; documenti, note, password e chat sono cifrati con la chiave di
  famiglia.
- **I prezzi non si scrivono mai** in un articolo: si linka `#prezzi`.
- Nei confronti **nessuna app concorrente per nome**, né affermazioni sui loro
  piani.
- Il piano Free copre due persone: dirlo quando un articolo parla di famiglie
  con più adulti.
- Note e liste sono visibili a **tutti** i membri, figli con account compresi:
  attenzione agli articoli su sorprese e regali.

## Funzioni da non inventare (errori già fatti traducendo)

La ricorrenza esiste **solo** negli eventi del calendario, non nelle cose da
fare. Non esistono: widget o scorciatoia dalla schermata di blocco per la spesa,
suggerimenti dei prodotti già comprati, storico interventi sui beni di Casa,
diario delle poppate, ricettario, storico della posizione.
Document Intelligence propone solo: spesa, evento, to-do, nota, intervento
veicolo, visita medica, vaccino, promemoria salute, rinomina documento.
La posizione è continua o temporanea 2/3/8 ore, con zone e raggio regolabile
(default 200 m). «Salva messaggio come to-do/evento/spesa/nota» **esiste solo su
iOS**. Quando una frase descrive una funzione, verificala nel codice o in
`FEATURES.md` prima di scriverla in quattro lingue.

## Le regole italiane invecchiano

Negli articoli su auto, documenti e salute ci sono regole di legge (revisione
4+2, RC senza tacito rinnovo, validità dei documenti dei minori 3/5 anni,
dichiarazione di accompagno sotto i 14, seggiolino e antiabbandono sotto i 4,
detrazione delle spese sanitarie con pagamento tracciabile). Se cambia la legge
vanno riallineate — e nelle traduzioni **si adattano al paese, non si
traducono**.

## Due trappole del generatore

- Un'etichetta come `**Prima:**` seguita **subito** da una riga `> …` finisce
  nello stesso blocco e il `>` esce come testo: serve una riga vuota prima della
  citazione.
- Nel footer **niente `<nav>`**: il CSS globale `nav{position:sticky…}` della
  barra in alto lo stravolge. Il footer è generato, **mai editarlo a mano**.

## SEO e consenso

- `kidboxapp.com` è verificato in Search Console con un TXT
  `google-site-verification=…` su IONOS: **non rimuoverlo**, e non usare la
  verifica automatica IONOS (voleva cancellare l'MX della posta).
- hreflang e sitemap coprono **solo le traduzioni esistenti**; un indice blog
  vuoto in una lingua va in `noindex` e fuori da sitemap e hreflang.
- **Mai rimettere `fbq` o `gtag` inline in una pagina**: Pixel e GA4 partono
  solo da `/assets/consent.js`, dopo il consenso, con finalità separate. Le
  pagine nuove includono quel file (i generatori lo fanno da soli), che porta
  anche il contatore di traffico della landing.
