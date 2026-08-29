# Verifica del dominio su Meta — perché `web.app` non basta

Stato: **bloccato lato Meta**, non lato codice. Il meta-tag è già in pagina; serve
un dominio proprio.

Documento **interno**: non sta in `docs/`, che GitHub Pages pubblica come sito
legale.

---

## 1. Il messaggio di Meta, tradotto

> «Non puoi verificare la tua azienda con un dominio del sito web comune»

Non è un problema del tag, della cache o dello scraping. È il **nome del
dominio**: `kidbox-landing.web.app` non è un dominio nostro, è un
**sottodominio** di `web.app`, che appartiene a Google ed è condiviso da tutti i
progetti Firebase Hosting del mondo.

`web.app` sta nella **Public Suffix List** — l'elenco dei suffissi sotto cui
chiunque può registrare un nome, come `.com` o `blogspot.com`. Meta rifiuta la
verifica su questi suffissi per una ragione sana: verificare `web.app`
significherebbe verificare *tutti* i siti Firebase, e verificare
`kidbox-landing.web.app` non dimostra il controllo di niente che Meta possa
attribuire a un'azienda.

**Nessun meta-tag, nessun record DNS e nessun caricamento di file può aggirarlo**:
i tre metodi di verifica di Meta dimostrano il controllo del dominio, e qui il
dominio non è nostro. Anche il metodo TXT su DNS è precluso, perché la zona
`web.app` la governa Google.

---

## 2. Cosa serve

Un dominio proprio, registrato a nome dell'azienda. Esempi coerenti col nome:
`kidbox.app`, `kidbox.family`, `kidboxapp.com`, `getkidbox.com`.

Poi:

1. **Registrare il dominio** presso un registrar (Cloudflare, Namecheap, Google
   Domains → Squarespace, Aruba…). Costo tipico 10–40 €/anno; `.app` richiede
   HTTPS obbligatorio, che con Firebase Hosting c'è già.
2. **Collegarlo a Firebase Hosting**: console Firebase → Hosting → *Aggiungi
   dominio personalizzato* → inserire il dominio → Firebase indica i record DNS
   (un TXT di verifica, poi due record A) da creare presso il registrar. Il
   certificato TLS lo emette Firebase da sé, in genere entro qualche ora.
3. **Il sito resta lo stesso**: stessa build, stesso `firebase deploy`. Il
   dominio `web.app` continua a funzionare come alias.
4. **Verificare su Meta** *quel* dominio, non più `kidbox-landing.web.app`. Il
   meta-tag è già nella `<head>` di `public/index.html` e
   `public/index-en.html`, quindi al momento del cambio non c'è altro da fare
   che rifare "Verify domain".

---

## 3. Stato del meta-tag in repo

Nella `<head>` delle due home page (italiana e inglese) ci sono **due** tag di
verifica:

| Codice | Nota |
|---|---|
| `2o2o5vykv3npb357big7t3116endd5` | primo tentativo, lasciato dov'era |
| `m4l9rhjzuzy05ipcdm7dspfduleeyj` | codice attuale |

Meta ammette più di un tag sulla stessa pagina (uno per asset o azienda), quindi
tenerli entrambi non fa danno. Sono statici e dentro `<head>`, come Meta
richiede: un tag iniettato da JavaScript non verrebbe letto.

Da rimuovere solo quando si è certi che il primo codice non serva più a nessun
asset.

---

## 4. Cosa NON risolve il problema

- Aspettare 72 ore: il rifiuto è immediato e categorico, non è un ritardo di
  scraping.
- Rigenerare il codice: cambia la stringa, non il dominio.
- Lo Sharing Debugger: mostrerebbe il tag correttamente letto e la verifica
  resterebbe comunque impossibile.
- Un sottodominio tipo `www.kidbox-landing.web.app`: è sempre sotto `web.app`.
