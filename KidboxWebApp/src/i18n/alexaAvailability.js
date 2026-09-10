/**
 * Se la sezione Alexa vada mostrata.
 *
 * La skill esiste **solo in `it-IT`**: il nome di invocazione è italiano e il
 * backend risponde in italiano. Mostrarne le istruzioni a chi usa KidBox in
 * un'altra lingua significa offrire una cosa che non può installare.
 *
 * Il segnale è la lingua **effettiva della web app**, la stessa scelta fatta
 * su iOS e Android (vedi `AlexaAvailability.swift` e `AlexaAvailability.kt`).
 *
 * ⚠️ Nascondendo la sezione si nasconde anche lo scollegamento: chi ha già
 * collegato Alexa e poi cambia lingua deve rimettere l'italiano per gestirlo.
 */
const SUPPORTED_LANGUAGES = ["it"];

export function isAlexaAvailable(locale) {
  return SUPPORTED_LANGUAGES.includes(locale);
}
