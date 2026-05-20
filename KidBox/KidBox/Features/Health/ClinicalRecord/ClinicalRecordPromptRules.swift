//
//  ClinicalRecordPromptRules.swift
//  KidBox
//

import Foundation

/// Regole testo condivise (client); mirror in `CLINICAL_RECORD_SYSTEM_RULES` su Firebase.
enum ClinicalRecordPromptRules {

    static let supplementalRules = """
    UNITÀ DI MISURA FARMACI (obbligatorio):
    Le unità dei farmaci devono essere corrette: compresse/capsule → mg o mcg (mai ml); farmaci liquidi orali → ml; iniettabili → mg/ml o UI.
    Esempio: Ezetimibe 10 mg (compressa), NON "10 millilitri".

    TRANSAMINASI E SOSPENSIONE STATINA:
    Se nei dati compaiono terapia sospesa/sostituita e rialzo transaminasi (GOT/GPT) nello stesso periodo, esplicita il nesso causale in prosa.
    Esempio: "Il rialzo della GPT fino a 96 U/L nel dicembre 2024 ha determinato la sospensione della terapia con statina, sostituita con Ezetimibe."

    PRESSIONE ARTERIOSA:
    NON creare una sezione standalone "PRESSIONE ARTERIOSA": i dati pressori vanno narrati solo dentro CARDIOLOGIA.
    Con più di 4 misurazioni PA nello stesso anno NON elencarle tutte: indica range min-max, valore più recente e tendenza.
    Esempio: "Nel corso del 2026 i valori pressori a riposo si sono attestati tra 120/70 e 121/84 mmHg, con tendenza alla stabilità."

    APPLE HEALTH / WEARABLE (solo se presenti nei dati):
    Sezione opzionale con disclaimer iniziale: dati da dispositivo consumer, valore indicativo non diagnostico.
    Commenta FC a riposo, VO2 max, minuti attività settimanali, SpO2 notturna, passi, HRV se disponibili; confronta con visite quando possibile;
    usa fasce di riferimento per età/sesso per VO2; chiudi con sintesi sul livello di attività fisica.
    """
}
