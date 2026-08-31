import { useEffect, useRef, useState } from "react";

/**
 * Disegna il codice a barre di un biglietto o di una tessera.
 *
 * Il formato arriva dai client nativi come raw value di `VNBarcodeSymbology`
 * (es. `VNBarcodeSymbologyQR`): qui si normalizza e si traduce nel nome che usa
 * bwip-js. Se il formato è ignoto si ripiega su QR, come fa iOS quando non
 * riesce a generare il simbolo originale.
 */
const ENCODERS = [
  [/pdf ?417/, "pdf417"],
  [/aztec/, "azteccode"],
  [/datamatrix/, "datamatrix"],
  [/qr/, "qrcode"],
  [/code ?128/, "code128"],
  [/code ?39/, "code39"],
  [/code ?93/, "code93"],
  [/ean ?13/, "ean13"],
  [/ean ?8/, "ean8"],
  [/upce/, "upce"],
  [/upca?/, "upca"],
  [/itf ?14/, "itf14"],
  [/(i2of5|interleaved)/, "interleaved2of5"],
];

export function encoderFor(format) {
  const f = (format || "").toLowerCase().replace("vnbarcodesymbology", "").replace(/[._-]/g, "");
  for (const [re, name] of ENCODERS) if (re.test(f)) return name;
  return "qrcode";
}

/**
 * Solo i simboli lineari vogliono un'altezza esplicita: su QR, Aztec e Data
 * Matrix `height` non ridimensiona, allunga i moduli — e un QR non quadrato non
 * si legge. PDF417 ha già la sua proporzione, quindi si lascia stare anche lui.
 */
const IS_LINEAR = new Set([
  "code128", "code39", "code93", "ean13", "ean8", "upce", "upca", "itf14", "interleaved2of5",
]);

function optionsFor(bcid, text) {
  const base = {
    bcid,
    text,
    scale: 3,
    includetext: false,
    backgroundcolor: "FFFFFF",
    paddingwidth: 8,
    paddingheight: 8,
  };
  return IS_LINEAR.has(bcid) ? { ...base, height: 14 } : base;
}

export default function Barcode({ text, format, className }) {
  const canvasRef = useRef(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (!text) return;
    let alive = true;
    setFailed(false);

    (async () => {
      // Import dinamico: bwip-js pesa, e serve solo a chi apre un biglietto.
      // Il pacchetto espone la build browser tramite condizione di export su ".":
      // Vite risolve da solo, non serve un sottopercorso.
      const bwipjs = (await import("bwip-js")).default;
      if (!alive || !canvasRef.current) return;
      const bcid = encoderFor(format);
      try {
        bwipjs.toCanvas(canvasRef.current, optionsFor(bcid, text));
      } catch {
        // Il testo non rispetta le regole del simbolo (es. lettere in un EAN):
        // meglio un QR leggibile che nessun codice.
        try {
          bwipjs.toCanvas(canvasRef.current, optionsFor("qrcode", text));
        } catch {
          if (alive) setFailed(true);
        }
      }
    })();

    return () => {
      alive = false;
    };
  }, [text, format]);

  if (!text) return null;
  if (failed) return <p className="wl-barcode-failed">{text}</p>;

  return (
    <div className={"wl-barcode " + (className || "")}>
      <canvas ref={canvasRef} />
      <span className="wl-barcode-text">{text}</span>
    </div>
  );
}
