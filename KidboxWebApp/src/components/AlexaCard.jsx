import { useCallback, useEffect, useRef, useState } from "react";
import { httpsCallable } from "firebase/functions";
import { functions } from "../firebase";
import { useFamily } from "../FamilyContext";
import { useTranslation } from "../i18n/LocaleContext";

/**
 * Collegamento fra questo account KidBox e la skill Alexa.
 *
 * Gemella della schermata iOS e Android (Features/Settings/Alexa). Qui vive
 * dentro Impostazioni invece che in una pagina sua, perché la pagina è già
 * fatta di card e una rotta in più per tre pulsanti non si giustifica.
 *
 * Perché un codice da dettare e non un login dentro la skill: l'account linking
 * di Alexa è OAuth2 e vuole una pagina di login propria, mentre i nostri account
 * nascono in gran parte da Google e Apple. Qui l'utente è già autenticato,
 * quindi il codice trasporta quell'identità senza chiedere di nuovo le
 * credenziali. Vedi internal/alexa/README.md.
 */
export default function AlexaCard() {
  const { currentFamilyId } = useFamily();
  const { t } = useTranslation();
  const a = t.alexa;

  const [status, setStatus] = useState(null);
  const [loading, setLoading] = useState(false);
  const [generating, setGenerating] = useState(false);
  const [error, setError] = useState(null);
  const [code, setCode] = useState(null);
  const [secondsLeft, setSecondsLeft] = useState(0);

  const expiresAtRef = useRef(0);

  const fetchStatus = useCallback(async () => {
    if (!currentFamilyId) return null;
    const res = await httpsCallable(functions, "getAlexaLinkStatus")({
      familyId: currentFamilyId,
    });
    setStatus(res.data);
    return res.data;
  }, [currentFamilyId]);

  useEffect(() => {
    if (!currentFamilyId) return;
    setLoading(true);
    fetchStatus()
      .catch(() => setError(a.errorStatus))
      .finally(() => setLoading(false));
  }, [currentFamilyId, fetchStatus, a.errorStatus]);

  // Conto alla rovescia più polling: la pagina non ha modo di sapere quando
  // l'utente ha finito di parlare all'Echo, quindi finché il codice è vivo si
  // richiede lo stato ogni pochi secondi e la card si aggiorna da sola.
  useEffect(() => {
    if (!code) return undefined;
    let elapsed = 0;
    const id = setInterval(async () => {
      const remaining = Math.round((expiresAtRef.current - Date.now()) / 1000);
      setSecondsLeft(Math.max(0, remaining));
      if (remaining <= 0) {
        setCode(null);
        return;
      }
      elapsed += 1;
      if (elapsed % 5 === 0) {
        // Silenzioso: un errore di rete non deve riempire la card di avvisi
        // mentre l'utente sta parlando.
        const fresh = await fetchStatus().catch(() => null);
        if (fresh?.linked && fresh?.voiceLinked) setCode(null);
      }
    }, 1000);
    return () => clearInterval(id);
  }, [code, fetchStatus]);

  const generate = async () => {
    if (!currentFamilyId) {
      setError(a.errorNoFamily);
      return;
    }
    setGenerating(true);
    setError(null);
    try {
      const res = await httpsCallable(functions, "createAlexaPairingCode")({
        familyId: currentFamilyId,
      });
      const raw = res.data?.code;
      const expires = res.data?.expiresAt;
      if (!raw || !expires) {
        setError(a.errorUnexpected);
        return;
      }
      expiresAtRef.current = expires;
      // "482915" → "482 915": a gruppi si detta senza perdere il segno.
      setCode(raw.length === 6 ? `${raw.slice(0, 3)} ${raw.slice(3)}` : raw);
      setSecondsLeft(Math.max(0, Math.round((expires - Date.now()) / 1000)));
    } catch {
      setError(a.errorCode);
    } finally {
      setGenerating(false);
    }
  };

  const unlink = async () => {
    if (!window.confirm(a.unlinkConfirm)) return;
    setLoading(true);
    setError(null);
    try {
      await httpsCallable(functions, "unlinkAlexa")({});
      setCode(null);
      await fetchStatus();
    } catch {
      setError(a.errorUnlink);
    } finally {
      setLoading(false);
    }
  };

  const linked = status?.linked === true;
  const voiceLinked = status?.voiceLinked === true;
  const others = (status?.familyLinks || []).filter((l) => l.uid && !l.isMe);

  // "Non collegata" sarebbe falso se un altro membro l'ha già agganciata: la
  // lista è già raggiungibile dagli Echo di casa.
  const headline = linked
    ? a.statusLinked
    : others.length > 0
      ? a.statusFamilyLinked
      : a.statusNotLinked;

  const detail = linked
    ? voiceLinked
      ? a.statusVoice
      : a.statusNoVoice
    : others.length > 0
      ? a.statusNotThisAccount
      : a.statusNeedsCode;

  const codeBlock = (
    <div className="alexa-code">
      <strong>{code}</strong>
      <small>{a.sayToAlexa}</small>
      <p>{a.linkPhrase(code)}</p>
      <small>
        {a.expiresIn(Math.floor(secondsLeft / 60), String(secondsLeft % 60).padStart(2, "0"))}
      </small>
    </div>
  );

  return (
    <section className="set-card">
      <h2>{a.title}</h2>

      <span className="set-row-text">
        <strong>{headline}</strong>
        <small>{loading ? a.checking : detail}</small>
      </span>

      <p className="pw-hint">{a.intro}</p>

      {others.length > 0 && (
        <>
          <h3 className="alexa-sub">{a.familySection}</h3>
          <ul className="alexa-members">
            {others.map((l) => (
              <li key={`${l.uid}-${l.kind}`}>
                <strong>{l.name || a.memberFallback}</strong>
                {/* Account e voce non sono la stessa cosa: il primo dà accesso
                    alla lista, la seconda solo l'attribuzione. */}
                <small>{l.kind === "voice" ? a.kindVoice : a.kindAccount}</small>
              </li>
            ))}
          </ul>
          <p className="pw-hint">{a.familyNote}</p>
        </>
      )}

      {/* Il codice non sparisce col collegamento dell'account: se la voce non è
          ancora associata serve ancora, ed è il caso del secondo membro di
          casa, che l'account ce l'ha già per riflesso. */}
      {!(linked && voiceLinked) &&
        (code ? (
          codeBlock
        ) : (
          <button className="prof-action" onClick={generate} disabled={generating}>
            {linked ? a.voiceCta : a.generate}
          </button>
        ))}

      {!(linked && voiceLinked) && (
        <p className="pw-hint">{linked ? a.voiceNote : a.pairingNote}</p>
      )}

      {linked && voiceLinked && (
        <>
          <h3 className="alexa-sub">{a.phrasesSection}</h3>
          <ul className="alexa-phrases">
            {a.phrases.map((p) => (
              <li key={p}>{p}</li>
            ))}
          </ul>
          <p className="pw-hint">{a.phrasesNote}</p>
          {/* Il promemoria e' l'unico comando che non si esaurisce in una
              frase: senza dirlo, l'utente sente la prima domanda e chiude.
              E' un vincolo di Amazon, non una scelta: AMAZON.SearchQuery,
              lo slot che regge il titolo libero, non puo' convivere con
              altri slot nella stessa frase. */}
          <p className="pw-hint">{a.remindNote}</p>
        </>
      )}

      {linked && (
        <button className="set-link alexa-unlink" onClick={unlink} disabled={loading}>
          {a.unlink}
        </button>
      )}

      {error && <p className="error">{error}</p>}
    </section>
  );
}
