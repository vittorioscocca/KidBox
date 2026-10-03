import { useEffect, useRef, useState } from "react";
import { fetchWalletPhoto } from "../services/walletPhotos";

/**
 * Due slot, FRONTE e RETRO, per le foto cifrate di una carta del Wallet
 * (tessera fedeltà o carta di pagamento). Slot vuoto = «+ Aggiungi foto»;
 * pieno = miniatura decifrata che si apre in una scheda nuova, con «Elimina».
 * Le foto si decifrano qui e gli object URL muoiono con il componente.
 *
 * `onUpload(side, file)` e `onRemove(side)` salvano anche la carta: lo slot
 * sa solo mostrare e chiedere.
 */
export default function CardPhotoSlots({ familyId, userId, frontPath, backPath, labels, onUpload, onRemove }) {
  const [photos, setPhotos] = useState({ front: null, back: null });
  const [busy, setBusy] = useState(null);
  const [error, setError] = useState(null);
  const fileRef = useRef(null);
  const pendingSide = useRef(null);

  useEffect(() => {
    let cancelled = false;
    const urls = [];
    const load = async (side, path) => {
      if (!path) return;
      try {
        const url = await fetchWalletPhoto({ familyId, userId, path });
        if (!url) return;
        urls.push(url);
        if (!cancelled) setPhotos((ph) => ({ ...ph, [side]: url }));
      } catch (err) {
        if (!cancelled) setError(err.message);
      }
    };
    setPhotos({ front: null, back: null });
    load("front", frontPath);
    load("back", backPath);
    return () => {
      cancelled = true;
      urls.forEach((u) => URL.revokeObjectURL(u));
    };
  }, [familyId, userId, frontPath, backPath]);

  const run = async (side, action) => {
    setBusy(side);
    setError(null);
    try {
      await action();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  const paths = { front: frontPath, back: backPath };

  return (
    <>
      <div className="pw-field-label">{labels.title}</div>
      <div className="wl-photos wl-photos-slots">
        {["front", "back"].map((side) => {
          const label = side === "front" ? labels.front : labels.back;
          return (
            <div key={side} className="wl-photo-slot">
              <span className="pw-detail-label">{label}</span>
              {photos[side] ? (
                <a href={photos[side]} target="_blank" rel="noopener noreferrer">
                  <img src={photos[side]} alt={label} />
                </a>
              ) : paths[side] ? (
                <span className="wl-photo-empty">…</span>
              ) : (
                <button
                  className="wl-photo-empty"
                  disabled={busy === side}
                  onClick={() => {
                    pendingSide.current = side;
                    fileRef.current?.click();
                  }}
                >
                  {busy === side ? "…" : `+ ${labels.add}`}
                </button>
              )}
              {paths[side] && busy !== side && (
                <button className="pw-danger wl-photo-remove" onClick={() => run(side, () => onRemove(side))}>
                  {labels.remove}
                </button>
              )}
            </div>
          );
        })}
      </div>
      {labels.hint && <p className="pw-hint">{labels.hint}</p>}
      {error && <p className="error">{error}</p>}
      <input
        ref={fileRef}
        type="file"
        accept="image/*"
        hidden
        onChange={(e) => {
          const f = e.target.files?.[0];
          e.target.value = "";
          const side = pendingSide.current;
          if (f && side) run(side, () => onUpload(side, f));
        }}
      />
    </>
  );
}
