# Privacy - Password breach check (HIBP)

KidBox verifica password compromesse con modello **k-anonymity**:

- La password in chiaro non lascia mai il dispositivo.
- Sul network viene inviato solo il prefisso SHA-1 di 5 caratteri (20 bit).
- Il server risponde con una lista di suffissi e conteggi, confrontati in locale.
- KidBox salva solo il verdetto numerico (`pwnedCount`) e il timestamp controllo (`pwnedCheckedAt`).
- Non vengono mai salvati hash completi o password in chiaro su Room/Firestore.
