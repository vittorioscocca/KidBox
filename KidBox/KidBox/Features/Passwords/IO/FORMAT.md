# KidBox Password Export Format (`.kbpw` / `.txt`)

Questa specifica descrive il formato testuale usato per import/export password di KidBox.

## File

- Nome consigliato: `KidBox-Passwords-<yyyy-MM-dd-HHmm>.txt`
- Estensione supportata: `.kbpw` o `.txt`
- Encoding: UTF-8 con BOM
- Separatore record: riga `---` (eventuali spazi ai lati ignorati)

## Header

Export non cifrato:

```text
# KidBox Password Export v1
```

Export cifrato con passphrase:

```text
# KidBox Password Export v1 (encrypted)
<base64 ciphertext>
```

`<base64 ciphertext>` contiene payload AES-GCM 256 derivato da passphrase.

## Record v1 (multilinea Key: value)

Ogni blocco rappresenta una password.

```text
---
Title: Gmail
Username: mario@example.com
Password: super-secret
WebSite: https://mail.google.com
Group: Personal
Visibility: family
Note: prima riga\nseconda riga
CreatedBy: uid-opzionale
Favorite: true
---
```

Chiavi supportate:

- `Title` (obbligatoria)
- `Username`
- `Password` (obbligatoria)
- `WebSite`
- `Group`
- `Visibility` (`family`, `members`, `private`)
- `Note`
- `CreatedBy` (UID Firebase; default utente corrente in import)
- `Favorite` (opzionale: `true` / `false`; default `false`)

## Escaping

Nel file export:

- newline `\n` viene serializzato come `\\n`
- backslash `\` viene serializzato come `\\\\`

In import avviene la conversione inversa.

## Formato legacy PassBox (supportato in import)

Riga singola:

```text
Account: <title> Group: <group> WebSite: <website> Username: <username> Password: <password> Note: <note>
```

Regex parser (multi-record, lookahead):

```regex
Account:\s(.*?)\sGroup:\s(.*?)\sWebSite:\s(.*?)\sUsername:\s(.*?)\sPassword:\s(.*?)\sNote:\s(.*?)(?=Account:\s|\z)
```

Implementazione parser consigliata:

- iOS: `NSRegularExpression` con opzione `.dotMatchesLineSeparators`
- Android: `Regex(..., RegexOption.DOT_MATCHES_ALL)` + `findAll`

### Limite noto formato PassBox

Se il valore di `Note` contiene la stringa letterale `Account: `, il parser può spezzare
il record in modo errato. Questo è un limite intrinseco del formato sorgente PassBox.

In import preview mostrare warning:

`Trovato testo ambiguo in N note — verifica i record N1, N2`.
