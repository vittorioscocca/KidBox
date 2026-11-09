import { useEffect, useRef } from "react";

/** Un QR disegnato in locale (bwip-js), senza testo sotto: per il passaggio della chiave. */
export default function QrCanvas({ text, className }) {
  const ref = useRef(null);
  useEffect(() => {
    let alive = true;
    (async () => {
      const bwipjs = (await import("bwip-js")).default;
      if (!alive || !ref.current) return;
      bwipjs.toCanvas(ref.current, {
        bcid: "qrcode",
        text,
        scale: 4,
        eclevel: "M",
        backgroundcolor: "FFFFFF",
        paddingwidth: 10,
        paddingheight: 10,
      });
    })();
    return () => {
      alive = false;
    };
  }, [text]);
  return <canvas ref={ref} className={className} aria-label="QR" />;
}
