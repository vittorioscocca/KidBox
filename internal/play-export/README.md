# Export manuale delle statistiche Play

L'export automatico su `gs://pubsite_prod_rev_00873204915190884037/stats/…`
si è fermato: l'ultimo file di settembre 2026 è stato scritto il 13/09 e
contiene dati fino all'8. In Play Console i numeri ci sono e sono aggiornati,
e la Play Developer Reporting API **non espone le installazioni** (solo crash,
ANR e vitals, che infatti restano freschi nel report).

Finché Google non riprende a scrivere nel bucket, la serie della base
installata si porta qui a mano:

1. Play Console → Statistiche → metrica **Installazioni attive**
   (o «Pubblico che ha eseguito l'installazione»), intervallo a piacere;
2. **Esporta report** → CSV;
3. salva il file in questa cartella, con un nome che finisce con la data
   dell'ultimo giorno contenuto (es. `installazioni-attive-2026-09-20.csv`).

`scripts/play-daily-report.js` legge da sola il file più recente di questa
cartella quando l'export del bucket è più vecchio, e lo dichiara nel report.
Il formato atteso è quello di Play Console: prima colonna `Data` in italiano
(`20 set 2026`), seconda colonna la metrica per «Tutti i paesi».
