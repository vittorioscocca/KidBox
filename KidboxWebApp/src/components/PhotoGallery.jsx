import { useCallback, useEffect, useRef, useState } from "react";
import { useTranslation } from "../i18n/LocaleContext";
import { fetchPhotoBlob, parseAlbumIds, setPhotoAlbums, setPhotoCaption, softDeletePhoto } from "../services/photos";
import "./PhotoGallery.css";

/**
 * Galleria a schermo intero: si scorre avanti e indietro fra tutti gli elementi,
 * con la striscia di miniature in basso — come il TabView paginato di
 * PhotoFullscreenView su iOS.
 *
 * Gli originali sono cifrati: ognuno va scaricato e decifrato al momento. Gli URL
 * già pronti restano in cache per la sessione, così tornare indietro è immediato.
 */
export default function PhotoGallery({
  photos,
  startIndex,
  albums,
  familyId,
  userId,
  onClose,
}) {
  const { t } = useTranslation();
  const [index, setIndex] = useState(startIndex);
  const [urls, setUrls] = useState({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [showAlbums, setShowAlbums] = useState(false);
  const [zoom, setZoom] = useState(1);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const dragRef = useRef(null);
  const stripRef = useRef(null);
  const cacheRef = useRef({});

  const photo = photos[index];

  const MAX_ZOOM = 5;

  const resetZoom = () => {
    setZoom(1);
    setOffset({ x: 0, y: 0 });
  };

  const applyZoom = (delta) => {
    setZoom((z) => {
      const next = Math.min(MAX_ZOOM, Math.max(1, z + delta));
      // Tornati a dimensione intera lo spostamento non ha senso: si ricentra.
      if (next === 1) setOffset({ x: 0, y: 0 });
      return next;
    });
  };

  const ensureLoaded = useCallback(
    async (target) => {
      if (!target || cacheRef.current[target.id]) return;
      setLoading(true);
      setError(null);
      try {
        const blob = await fetchPhotoBlob({ familyId, userId, photo: target });
        const url = URL.createObjectURL(blob);
        cacheRef.current[target.id] = url;
        setUrls((prev) => ({ ...prev, [target.id]: url }));
      } catch (err) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    },
    [familyId, userId]
  );

  useEffect(() => {
    ensureLoaded(photos[index]);
    setZoom(1);
    setOffset({ x: 0, y: 0 });
  }, [index, photos, ensureLoaded]);

  // Gli URL blob vanno revocati all'uscita, altrimenti restano in memoria.
  useEffect(() => {
    const cache = cacheRef.current;
    return () => Object.values(cache).forEach(URL.revokeObjectURL);
  }, []);

  const go = useCallback(
    (delta) => {
      setIndex((i) => Math.min(photos.length - 1, Math.max(0, i + delta)));
    },
    [photos.length]
  );

  // Frecce e Esc: navigare una galleria con la tastiera è la norma su desktop.
  useEffect(() => {
    const onKey = (e) => {
      if (e.key === "ArrowRight") go(1);
      else if (e.key === "ArrowLeft") go(-1);
      else if (e.key === "Escape") onClose();
      else if (e.key === "+" || e.key === "=") applyZoom(0.5);
      else if (e.key === "-") applyZoom(-0.5);
      else if (e.key === "0") resetZoom();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [go, onClose]);

  // Tiene la miniatura corrente sempre visibile nella striscia.
  useEffect(() => {
    const strip = stripRef.current;
    const active = strip?.querySelector(".strip-thumb.active");
    active?.scrollIntoView({ behavior: "smooth", inline: "center", block: "nearest" });
  }, [index]);

  // Trascinamento attivo solo da ingrandita, altrimenti si "muoverebbe" un'immagine
  // che è già tutta visibile.
  const onPointerDown = (e) => {
    if (zoom === 1) return;
    dragRef.current = { x: e.clientX - offset.x, y: e.clientY - offset.y };
    e.currentTarget.setPointerCapture(e.pointerId);
  };

  const onPointerMove = (e) => {
    if (!dragRef.current) return;
    setOffset({ x: e.clientX - dragRef.current.x, y: e.clientY - dragRef.current.y });
  };

  const onPointerUp = () => {
    dragRef.current = null;
  };

  if (!photo) return null;

  const url = urls[photo.id];
  const isVideo = (photo.mimeType ?? "").startsWith("video/");
  const inAlbums = parseAlbumIds(photo.albumIdsRaw);

  const download = () => {
    if (!url) return;
    const a = document.createElement("a");
    a.href = url;
    a.download = photo.fileName || "media";
    a.click();
  };

  return (
    <div className="gallery-overlay" onClick={onClose}>
      <div className="gallery-panel" onClick={(e) => e.stopPropagation()}>
        <div className="gallery-bar">
          <span className="gallery-title">{photo.fileName}</span>
          <span className="gallery-position">
            {t.photos.position(index + 1, photos.length)}
          </span>
          <div className="viewer-actions">
            {!isVideo && (
              <>
                <button
                  onClick={() => applyZoom(-0.5)}
                  disabled={zoom <= 1}
                  title={t.photos.zoomOut}
                >
                  −
                </button>
                <span className="zoom-level">{Math.round(zoom * 100)}%</span>
                <button
                  onClick={() => applyZoom(0.5)}
                  disabled={zoom >= 5}
                  title={t.photos.zoomIn}
                >
                  ＋
                </button>
                <button onClick={resetZoom} disabled={zoom === 1} title={t.photos.zoomReset}>
                  ⤢
                </button>
              </>
            )}
            <button onClick={() => setShowAlbums((v) => !v)} title={t.photos.addToAlbum}>
              🗂
            </button>
            <button onClick={download} title={t.photos.download} disabled={!url}>
              ⬇
            </button>
            <button
              onClick={async () => {
                if (!window.confirm(t.photos.deletePhotoConfirm)) return;
                await softDeletePhoto({ familyId, userId, photoId: photo.id });
                if (photos.length <= 1) onClose();
                else go(index === photos.length - 1 ? -1 : 1);
              }}
              title={t.photos.deletePhoto}
            >
              🗑
            </button>
            <button onClick={onClose}>✕</button>
          </div>
        </div>

        <div className="gallery-stage">
          <button
            className="gallery-nav prev"
            onClick={() => go(-1)}
            disabled={index === 0}
            title={t.photos.prev}
          >
            ‹
          </button>

          <div className="gallery-media">
            {error && <p className="error">{error}</p>}
            {!url && !error && (
              // Finché l'originale non è pronto si mostra la miniatura ingrandita:
              // sfocata ma immediata, invece di un riquadro vuoto.
              <div className="gallery-loading">
                {photo.thumbnailBase64 && (
                  <img
                    className="gallery-preview"
                    src={`data:image/jpeg;base64,${photo.thumbnailBase64}`}
                    alt=""
                  />
                )}
                {loading && <span className="gallery-spinner">{t.photos.loading}</span>}
              </div>
            )}
            {url &&
              (isVideo ? (
                <video src={url} controls autoPlay />
              ) : (
                <img
                  src={url}
                  alt={photo.caption || photo.fileName}
                  className={"zoomable" + (zoom > 1 ? " zoomed" : "")}
                  style={{
                    transform: `translate(${offset.x}px, ${offset.y}px) scale(${zoom})`,
                  }}
                  onDoubleClick={() => (zoom > 1 ? resetZoom() : applyZoom(1))}
                  onWheel={(e) => {
                    if (!e.ctrlKey && !e.metaKey) return;
                    e.preventDefault();
                    applyZoom(e.deltaY < 0 ? 0.3 : -0.3);
                  }}
                  onPointerDown={onPointerDown}
                  onPointerMove={onPointerMove}
                  onPointerUp={onPointerUp}
                  onPointerCancel={onPointerUp}
                  draggable={false}
                />
              ))}
          </div>

          <button
            className="gallery-nav next"
            onClick={() => go(1)}
            disabled={index === photos.length - 1}
            title={t.photos.next}
          >
            ›
          </button>
        </div>

        {showAlbums && (
          <div className="viewer-albums">
            {albums.length === 0 && <span className="dim">{t.photos.noAlbums}</span>}
            {albums.map((a) => (
              <button
                key={a.id}
                className={"cat-chip" + (inAlbums.includes(a.id) ? " active" : "")}
                onClick={() =>
                  setPhotoAlbums({
                    familyId,
                    userId,
                    photoId: photo.id,
                    albumIds: inAlbums.includes(a.id)
                      ? inAlbums.filter((x) => x !== a.id)
                      : [...inAlbums, a.id],
                  })
                }
              >
                {inAlbums.includes(a.id) ? "✓ " : ""}
                {a.title}
              </button>
            ))}
          </div>
        )}

        <div className="viewer-caption">
          <input
            key={photo.id}
            placeholder={t.photos.captionPlaceholder}
            defaultValue={photo.caption ?? ""}
            onBlur={(e) =>
              setPhotoCaption({
                familyId,
                userId,
                photoId: photo.id,
                caption: e.target.value,
              })
            }
          />
        </div>

        <div className="gallery-strip" ref={stripRef}>
          {photos.map((p, i) => (
            <button
              key={p.id}
              className={"strip-thumb" + (i === index ? " active" : "")}
              onClick={() => setIndex(i)}
            >
              {p.thumbnailBase64 ? (
                <img src={`data:image/jpeg;base64,${p.thumbnailBase64}`} alt="" />
              ) : (
                <span>{(p.mimeType ?? "").startsWith("video/") ? "🎬" : "🖼"}</span>
              )}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
