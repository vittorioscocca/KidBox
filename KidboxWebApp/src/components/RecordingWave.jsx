/**
 * Onda che scorre mentre si registra un vocale.
 *
 * Non è decorazione: dice che il microfono sta prendendo davvero il suono, e
 * quanto forte. Il livello si legge dall'`AnalyserNode` sullo stesso stream che
 * sta registrando — nessuna seconda presa dal microfono.
 *
 * Il valore è la potenza del segnale (RMS) della finestra corrente, non un
 * campione singolo: un campione preso a caso salterebbe a caso, l'RMS segue la
 * voce.
 */
import { useEffect, useRef, useState } from "react";

/** Larghezza di una colonna più il suo spazio: decide quante ce ne stanno. */
const COLUMN_PX = 11;
const MIN_COLUMNS = 20;
const MAX_COLUMNS = 140;
/** ~18 colonne al secondo: l'occhio la vede scorrere, la chat non si ridisegna
 *  a ogni fotogramma. */
const FRAME_MS = 55;

export default function RecordingWave({ stream }) {
  const boxRef = useRef(null);
  const [levels, setLevels] = useState([]);
  /**
   * Quante colonne stanno nella riga. Fisse com'erano, su una finestra larga
   * l'onda diventava un trattino in fondo a una barra vuota: qui si contano
   * quelle che servono per riempire lo spazio che c'è davvero.
   */
  const [columns, setColumns] = useState(MIN_COLUMNS);

  useEffect(() => {
    const box = boxRef.current;
    if (!box) return undefined;
    const measure = () => {
      const width = box.clientWidth;
      if (!width) return;
      setColumns(Math.max(MIN_COLUMNS, Math.min(MAX_COLUMNS, Math.floor(width / COLUMN_PX))));
    };
    measure();
    if (typeof ResizeObserver === "undefined") return undefined;
    const observer = new ResizeObserver(measure);
    observer.observe(box);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (!stream) return undefined;
    const Context = window.AudioContext || window.webkitAudioContext;
    if (!Context) return undefined;

    const context = new Context();
    // Creato fuori dal gesto dell'utente (l'effetto parte dopo il render), un
    // AudioContext nasce sospeso: l'analizzatore leggerebbe silenzio e l'onda
    // resterebbe piatta. `resume()` è concesso perché il clic sul microfono è
    // appena avvenuto.
    context.resume?.().catch(() => {});
    const source = context.createMediaStreamSource(stream);
    const analyser = context.createAnalyser();
    analyser.fftSize = 1024;
    source.connect(analyser);

    const samples = new Uint8Array(analyser.fftSize);

    // Un intervallo e non `requestAnimationFrame`: qui si campiona un livello
    // audio a passo fisso, non si insegue il refresh dello schermo — e così
    // l'onda continua a scorrere anche quando la finestra non è in primo
    // piano, invece di congelarsi e ripartire con uno scatto.
    const timer = setInterval(() => {
      analyser.getByteTimeDomainData(samples);
      let sum = 0;
      for (let i = 0; i < samples.length; i += 1) {
        const value = (samples[i] - 128) / 128;
        sum += value * value;
      }
      const rms = Math.sqrt(sum / samples.length);
      // Il parlato normale sta molto sotto il fondo scala: senza guadagno
      // l'onda resterebbe una linea piatta.
      const level = Math.min(1, rms * 3.2);
      setLevels((previous) => [...previous, level].slice(-MAX_COLUMNS));
    }, FRAME_MS);

    return () => {
      clearInterval(timer);
      source.disconnect();
      context.close();
    };
  }, [stream]);

  // A inizio registrazione le colonne mancanti sono piatte a sinistra: l'onda
  // entra da destra invece di apparire tutta insieme.
  const shown = levels.slice(-columns);
  const padding = Array(Math.max(0, columns - shown.length)).fill(0);

  return (
    <div className="chat-rec-wave" ref={boxRef} aria-hidden="true">
      {[...padding, ...shown].map((level, i) => (
        <span
          key={i}
          // Le colonne non ancora incise restano una guida smorzata: a tutta
          // tinta, su una finestra larga, sembravano una riga tratteggiata.
          className={level > 0 ? "" : "idle"}
          style={{ height: `${Math.round(8 + level * 92)}%` }}
        />
      ))}
    </div>
  );
}
