/**
 * Messaggio vocale con l'aspetto di WhatsApp: tasto tondo, onda, tempo che
 * scorre e velocità di riproduzione — al posto del player nativo del browser,
 * che su Mac è una barra grigia di sistema, larga il doppio della bolla e
 * fuori tono con tutto il resto.
 *
 * L'onda è quella vera del file: alla prima riproduzione l'audio viene decodificato
 * una volta e ridotto a 48 barre di ampiezza. Finché non è pronta — e per sempre,
 * se il browser non sa decodificare quel formato — si mostra un'onda di
 * riempimento **stabile**, generata dall'URL del messaggio: non è l'ampiezza
 * reale, ma non balla a ogni render e non fa sembrare rotta la bolla.
 */
import { useEffect, useMemo, useRef, useState } from "react";
import { formatDuration } from "./chatFormat";

const RATES = [1, 1.5, 2];
const BARS = 38;
/** Oltre questa soglia non si decodifica: è un vocale, non un album. */
const MAX_DECODE_BYTES = 12 * 1024 * 1024;

/**
 * Contenitore riconosciuto dai primi byte, non dall'etichetta.
 *
 * Serve ai vocali già su Storage: prima che il client web dichiarasse il
 * formato vero, ogni registrazione veniva caricata come `audio/mp4` anche
 * quando era WebM. Chrome li apre lo stesso perché annusa il contenuto, Safari
 * no — e questo permette di rimediare senza toccare i file.
 */
function sniffAudioType(bytes) {
  const head = new Uint8Array(bytes.slice(0, 12));
  const ascii = (from, to) => String.fromCharCode(...head.slice(from, to));
  if (ascii(4, 8) === "ftyp") return "audio/mp4";
  if (head[0] === 0x1a && head[1] === 0x45 && head[2] === 0xdf && head[3] === 0xa3) return "audio/webm";
  if (ascii(0, 4) === "OggS") return "audio/ogg";
  if (ascii(0, 4) === "RIFF" && ascii(8, 12) === "WAVE") return "audio/wav";
  if (ascii(0, 3) === "ID3" || (head[0] === 0xff && (head[1] & 0xe0) === 0xe0)) return "audio/mpeg";
  return null;
}

/** PRNG deterministico: stesso URL, stessa onda, a ogni apertura della chat. */
function seededBars(seed) {
  let state = 0;
  for (let i = 0; i < seed.length; i += 1) state = (state * 31 + seed.charCodeAt(i)) >>> 0;
  const next = () => {
    state += 0x6d2b79f5;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  // Una parlata non è rumore bianco: si parte basso, si sale, si scende.
  return Array.from({ length: BARS }, (_, i) => {
    const envelope = Math.sin((Math.PI * (i + 1)) / (BARS + 1)) ** 0.5;
    return 0.18 + 0.82 * envelope * (0.45 + 0.55 * next());
  });
}

/** Il file decodificato ridotto a `BARS` valori: il picco di ogni finestra. */
function peaksFrom(buffer) {
  const data = buffer.getChannelData(0);
  const window = Math.floor(data.length / BARS) || 1;
  const peaks = [];
  let max = 0;
  for (let i = 0; i < BARS; i += 1) {
    let peak = 0;
    for (let j = i * window; j < (i + 1) * window && j < data.length; j += 1) {
      const value = Math.abs(data[j]);
      if (value > peak) peak = value;
    }
    peaks.push(peak);
    if (peak > max) max = peak;
  }
  // Normalizzato sul picco del file: un vocale registrato piano deve vedersi
  // come uno registrato forte.
  return peaks.map((p) => 0.12 + 0.88 * (max > 0 ? p / max : 0));
}

export default function ChatAudioPlayer({ url, duration }) {
  const audioRef = useRef(null);
  const waveRef = useRef(null);
  const decodeStarted = useRef(false);

  const [playing, setPlaying] = useState(false);
  const [current, setCurrent] = useState(0);
  const [length, setLength] = useState(duration || 0);
  const [rate, setRate] = useState(1);
  const [failed, setFailed] = useState(false);
  const [peaks, setPeaks] = useState(null);
  /** Sorgente ricostruita col tipo giusto, quando quella originale è rifiutata. */
  const [rescued, setRescued] = useState(null);
  const rescueTried = useRef(false);

  const fallback = useMemo(() => seededBars(url || ""), [url]);
  const bars = peaks || fallback;
  const progress = length > 0 ? Math.min(1, current / length) : 0;

  useEffect(() => {
    // Cambia il messaggio: si riparte da zero, senza portarsi dietro l'onda
    // del vocale precedente.
    decodeStarted.current = false;
    rescueTried.current = false;
    setPeaks(null);
    setCurrent(0);
    setPlaying(false);
    setFailed(false);
    setRescued((old) => {
      if (old) URL.revokeObjectURL(old);
      return null;
    });
  }, [url]);

  // L'ultimo `blob:` creato va restituito, altrimenti resta in memoria per
  // tutta la sessione.
  useEffect(() => () => {
    if (rescued) URL.revokeObjectURL(rescued);
  }, [rescued]);

  /**
   * Il browser ha rifiutato il file: si riscarica, si guarda com'è fatto
   * davvero e si riprova una volta sola con il tipo corretto.
   */
  const rescueOnce = async () => {
    if (rescueTried.current || !url) return false;
    rescueTried.current = true;
    try {
      const response = await fetch(url);
      if (!response.ok) return false;
      const raw = await response.arrayBuffer();
      const type = sniffAudioType(raw);
      if (!type) return false;
      setRescued(URL.createObjectURL(new Blob([raw], { type })));
      setFailed(false);
      return true;
    } catch {
      return false;
    }
  };

  /** Decodifica una sola volta, alla prima riproduzione: prima di allora non
   *  vale la pena scaricare il file di ogni vocale della conversazione. */
  const decodeOnce = async () => {
    if (decodeStarted.current || !url) return;
    decodeStarted.current = true;
    const Context = window.AudioContext || window.webkitAudioContext;
    if (!Context) return;
    let context;
    try {
      const response = await fetch(url);
      if (!response.ok) return;
      const raw = await response.arrayBuffer();
      if (raw.byteLength > MAX_DECODE_BYTES) return;
      context = new Context();
      const decoded = await context.decodeAudioData(raw);
      setPeaks(peaksFrom(decoded));
      if (!duration && decoded.duration) setLength(decoded.duration);
    } catch {
      // Formato che questo browser non sa decodificare (capita con il webm/opus
      // su Safari): resta l'onda di riempimento, la riproduzione non c'entra.
    } finally {
      context?.close?.();
    }
  };

  const toggle = () => {
    const audio = audioRef.current;
    if (!audio) return;
    if (audio.paused) {
      decodeOnce();
      audio.playbackRate = rate;
      audio.play().catch(() => setFailed(true));
    } else {
      audio.pause();
    }
  };

  const cycleRate = () => {
    const next = RATES[(RATES.indexOf(rate) + 1) % RATES.length];
    setRate(next);
    if (audioRef.current) audioRef.current.playbackRate = next;
  };

  /** Salto nel punto toccato dell'onda, come sul telefono. */
  const seek = (event) => {
    const audio = audioRef.current;
    const box = waveRef.current?.getBoundingClientRect();
    if (!audio || !box || !length) return;
    const ratio = Math.min(1, Math.max(0, (event.clientX - box.left) / box.width));
    audio.currentTime = ratio * length;
    setCurrent(ratio * length);
  };

  // A riproduzione ferma si legge la durata, come su WhatsApp; mentre suona,
  // il tempo trascorso.
  const shownTime = playing || current > 0 ? current : length;

  return (
    <div className={"chat-audio" + (failed ? " failed" : "")}>
      <audio
        ref={audioRef}
        src={rescued || url}
        preload="metadata"
        onLoadedMetadata={(e) => {
          const value = e.currentTarget.duration;
          if (Number.isFinite(value) && value > 0) setLength(value);
        }}
        onTimeUpdate={(e) => setCurrent(e.currentTarget.currentTime)}
        onPlay={() => setPlaying(true)}
        onPause={() => setPlaying(false)}
        onEnded={() => {
          setPlaying(false);
          setCurrent(0);
        }}
        onError={() => {
          rescueOnce().then((saved) => {
            if (!saved) setFailed(true);
          });
        }}
      />

      <button
        className="chat-audio-play"
        onClick={toggle}
        disabled={failed}
        aria-label={playing ? "Metti in pausa" : "Riproduci"}
      >
        {playing ? (
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <rect x="7" y="5" width="3.6" height="14" rx="1.2" />
            <rect x="13.4" y="5" width="3.6" height="14" rx="1.2" />
          </svg>
        ) : (
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M8 5.2v13.6L19 12z" />
          </svg>
        )}
      </button>

      <div className="chat-audio-body">
        <div
          className="chat-wave"
          ref={waveRef}
          onPointerDown={seek}
          role="presentation"
        >
          {bars.map((value, i) => (
            <span
              key={i}
              className={i / BARS < progress ? "on" : ""}
              style={{ height: `${Math.round(value * 100)}%` }}
            />
          ))}
          {/* La testina: dice dove si è arrivati e che l'onda si può toccare. */}
          <i className="chat-wave-head" style={{ left: `${progress * 100}%` }} />
        </div>
        <div className="chat-audio-meta">
          <span>{failed ? "Audio non riproducibile" : formatDuration(shownTime)}</span>
          <button className="chat-audio-rate" onClick={cycleRate}>
            {rate}×
          </button>
        </div>
      </div>
    </div>
  );
}
