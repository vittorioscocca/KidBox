import { useEffect, useMemo, useRef, useState } from "react";
import { collection, onSnapshot, query, where } from "firebase/firestore";
import { db } from "../firebase";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import { MissingFamilyKeyError, loadFamilyKey } from "../services/familyKey";
import {
  createAlbum,
  deleteAlbum,
  fetchPhotoBlob,
  parseAlbumIds,
  renameAlbum,
  setPhotoAlbums,
  softDeletePhoto,
  uploadPhoto,
} from "../services/photos";
import PhotoGallery from "../components/PhotoGallery";
import Modal from "../components/Modal";
import "./Foto.css";

const GROUPINGS = ["year", "month", "all"];

/**
 * I tre livelli non sono semplici intestazioni ma una navigazione a scendere,
 * come in Foto di iOS: da "Anni" si vede una copertina per anno, entrando si
 * vedono i mesi di quell'anno, entrando ancora tutte le foto del mese.
 * "Tutto" mostra la libreria intera senza suddivisioni.
 */
function yearOf(photo) {
  return photo.takenAt?.toDate?.()?.getFullYear() ?? null;
}

function monthOf(photo) {
  const d = photo.takenAt?.toDate?.();
  return d ? d.getMonth() : null;
}

function monthLabel(year, month, locale) {
  const s = new Intl.DateTimeFormat(locale === "en" ? "en-US" : "it-IT", {
    month: "long",
    year: "numeric",
  }).format(new Date(year, month, 1));
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function formatDuration(seconds) {
  if (!seconds) return null;
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

export default function Foto() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();

  const [tab, setTab] = useState("photos");
  const [grouping, setGrouping] = useState(
    () => localStorage.getItem("kidbox:photoGrouping") || "year"
  );
  const [yearFilter, setYearFilter] = useState(null);
  const [monthFilter, setMonthFilter] = useState(null);
  const [photos, setPhotos] = useState([]);
  const [albums, setAlbums] = useState([]);
  const [openAlbum, setOpenAlbum] = useState(null);
  const [keyError, setKeyError] = useState(null);
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(null);
  const [galleryIndex, setGalleryIndex] = useState(null);
  const [selectionMode, setSelectionMode] = useState(false);
  const [selected, setSelected] = useState(() => new Set());
  const [albumPicker, setAlbumPicker] = useState(false);
  const [newAlbumOpen, setNewAlbumOpen] = useState(false);
  const [renamingAlbum, setRenamingAlbum] = useState(null);
  const fileInput = useRef(null);

  useEffect(() => {
    setKeyError(null);
    if (!currentFamilyId || !user) return;
    loadFamilyKey({ familyId: currentFamilyId, userId: user.uid }).catch((err) =>
      setKeyError(err instanceof MissingFamilyKeyError ? "missing" : err.message)
    );
  }, [currentFamilyId, user]);

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    const q = query(
      collection(db, "families", currentFamilyId, "photos"),
      where("isDeleted", "==", false)
    );
    return onSnapshot(
      q,
      (snap) => setPhotos(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (err) => setError(err.message)
    );
  }, [currentFamilyId]);

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    const q = query(
      collection(db, "families", currentFamilyId, "photoAlbums"),
      where("isDeleted", "==", false)
    );
    return onSnapshot(
      q,
      (snap) => setAlbums(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (err) => setError(err.message)
    );
  }, [currentFamilyId]);

  const visiblePhotos = useMemo(() => {
    const base = openAlbum
      ? photos.filter((p) => parseAlbumIds(p.albumIdsRaw).includes(openAlbum.id))
      : photos;
    return [...base].sort(
      (a, b) => (b.takenAt?.toMillis?.() ?? 0) - (a.takenAt?.toMillis?.() ?? 0)
    );
  }, [photos, openAlbum]);

  /** Foto della libreria filtrate dalla navigazione corrente. */
  const scopedPhotos = useMemo(
    () =>
      visiblePhotos.filter(
        (p) =>
          (yearFilter === null || yearOf(p) === yearFilter) &&
          (monthFilter === null || monthOf(p) === monthFilter)
      ),
    [visiblePhotos, yearFilter, monthFilter]
  );

  /** Un riquadro per anno, con copertina e conteggio. */
  const yearSummaries = useMemo(() => {
    const map = new Map();
    visiblePhotos.forEach((p) => {
      const y = yearOf(p);
      if (y === null) return;
      if (!map.has(y)) map.set(y, []);
      map.get(y).push(p);
    });
    return [...map.entries()]
      .sort((a, b) => b[0] - a[0])
      .map(([year, items]) => ({
        year,
        count: items.length,
        cover: items.find((p) => p.thumbnailBase64) ?? items[0],
      }));
  }, [visiblePhotos]);

  /** Un riquadro per mese, con qualche anteprima invece di tutte le foto. */
  const monthSummaries = useMemo(() => {
    const base =
      yearFilter === null
        ? visiblePhotos
        : visiblePhotos.filter((p) => yearOf(p) === yearFilter);
    const map = new Map();
    base.forEach((p) => {
      const d = p.takenAt?.toDate?.();
      if (!d) return;
      const key = `${d.getFullYear()}-${d.getMonth()}`;
      if (!map.has(key)) map.set(key, { year: d.getFullYear(), month: d.getMonth(), items: [] });
      map.get(key).items.push(p);
    });
    return [...map.values()].sort(
      (a, b) => b.year - a.year || b.month - a.month
    );
  }, [visiblePhotos, yearFilter]);

  const changeGrouping = (value) => {
    localStorage.setItem("kidbox:photoGrouping", value);
    setGrouping(value);
    setYearFilter(null);
    setMonthFilter(null);
  };

  const openYear = (year) => {
    setYearFilter(year);
    setMonthFilter(null);
    setGrouping("month");
  };

  const openMonth = (year, month) => {
    setYearFilter(year);
    setMonthFilter(month);
    setGrouping("all");
  };

  const handleFiles = async (fileList) => {
    const files = [...fileList];
    if (!files.length) return;
    setError(null);
    try {
      for (let i = 0; i < files.length; i += 1) {
        setBusy(t.photos.uploading(i + 1, files.length));
        await uploadPhoto({
          familyId: currentFamilyId,
          userId: user.uid,
          file: files[i],
          albumIds: openAlbum ? [openAlbum.id] : [],
        });
      }
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  const exitSelection = () => {
    setSelectionMode(false);
    setSelected(new Set());
  };

  const toggleSelected = (id) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const selectedPhotos = scopedPhotos.filter((p) => selected.has(p.id));

  /** Scarica in sequenza: il browser blocca decine di download simultanei. */
  const downloadSelected = async () => {
    setError(null);
    try {
      for (let i = 0; i < selectedPhotos.length; i += 1) {
        setBusy(t.photos.uploading(i + 1, selectedPhotos.length));
        const photo = selectedPhotos[i];
        const blob = await fetchPhotoBlob({
          familyId: currentFamilyId,
          userId: user.uid,
          photo,
        });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = photo.fileName || "media";
        a.click();
        URL.revokeObjectURL(url);
      }
      exitSelection();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  const deleteSelected = async () => {
    if (!window.confirm(t.photos.deleteSelectedConfirm(selectedPhotos.length))) return;
    setBusy(t.photos.loading);
    try {
      await Promise.all(
        selectedPhotos.map((p) =>
          softDeletePhoto({
            familyId: currentFamilyId,
            userId: user.uid,
            photoId: p.id,
          })
        )
      );
      exitSelection();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  /** Aggiunge all'album senza toglierle dagli altri in cui già sono. */
  const moveSelectedToAlbum = async (albumId) => {
    setBusy(t.photos.loading);
    try {
      await Promise.all(
        selectedPhotos.map((p) => {
          const current = parseAlbumIds(p.albumIdsRaw);
          if (current.includes(albumId)) return null;
          return setPhotoAlbums({
            familyId: currentFamilyId,
            userId: user.uid,
            photoId: p.id,
            albumIds: [...current, albumId],
          });
        })
      );
      setAlbumPicker(false);
      exitSelection();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  if (keyError === "missing") {
    return (
      <div className="notes-locked">
        <div className="locked-icon">🔒</div>
        <h2>{t.photos.keyMissing}</h2>
        <p>{t.photos.keyMissingHint}</p>
      </div>
    );
  }

  const showingAlbums = tab === "albums" && !openAlbum;

  return (
    <div className="photos-page">
      <div className="photos-toolbar">
        <div className="seg-control">
          <button
            className={"seg-btn" + (tab === "photos" && !openAlbum ? " active" : "")}
            onClick={() => {
              setTab("photos");
              setOpenAlbum(null);
            }}
          >
            {t.photos.tabPhotos}
          </button>
          <button
            className={"seg-btn" + (tab === "albums" ? " active" : "")}
            onClick={() => {
              setTab("albums");
              setOpenAlbum(null);
            }}
          >
            {t.photos.tabAlbums}
          </button>
        </div>

        {!showingAlbums && visiblePhotos.length > 0 && (
          <div className="seg-control group-picker">
            {GROUPINGS.map((g) => (
              <button
                key={g}
                className={"seg-btn" + (grouping === g ? " active" : "")}
                onClick={() => changeGrouping(g)}
              >
                {t.photos[`group${g.charAt(0).toUpperCase()}${g.slice(1)}`]}
              </button>
            ))}
          </div>
        )}

        {!showingAlbums && grouping === "all" && scopedPhotos.length > 0 && (
          <button
            className={"docs-btn" + (selectionMode ? " active" : "")}
            onClick={() => (selectionMode ? exitSelection() : setSelectionMode(true))}
          >
            {selectionMode ? `✓ ${t.photos.selectDone}` : `☑ ${t.photos.select}`}
          </button>
        )}

        {showingAlbums ? (
          <button className="docs-btn" onClick={() => setNewAlbumOpen(true)}>
            ＋ {t.photos.newAlbum}
          </button>
        ) : (
          <button className="docs-btn" onClick={() => fileInput.current?.click()}>
            ⬆ {t.photos.upload}
          </button>
        )}
        <input
          ref={fileInput}
          type="file"
          accept="image/*,video/*"
          multiple
          hidden
          onChange={(e) => {
            handleFiles(e.target.files);
            e.target.value = "";
          }}
        />
      </div>

      {!showingAlbums && (yearFilter !== null || monthFilter !== null) && (
        <div className="docs-breadcrumb">
          <button onClick={() => changeGrouping("year")}>{t.photos.allYears}</button>
          {yearFilter !== null && (
            <>
              <span className="crumb-sep">›</span>
              <button
                onClick={() => {
                  setMonthFilter(null);
                  setGrouping("month");
                }}
              >
                {yearFilter}
              </button>
            </>
          )}
          {monthFilter !== null && yearFilter !== null && (
            <>
              <span className="crumb-sep">›</span>
              <strong>{monthLabel(yearFilter, monthFilter, locale)}</strong>
            </>
          )}
        </div>
      )}

      {openAlbum && (
        <div className="docs-breadcrumb">
          <button onClick={() => setOpenAlbum(null)}>{t.photos.tabAlbums}</button>
          <span className="crumb-sep">›</span>
          <strong>{openAlbum.title}</strong>
        </div>
      )}

      {selectionMode && selected.size > 0 && (
        <div className="selection-bar">
          <span>{t.photos.selected(selected.size)}</span>
          <button className="docs-btn" onClick={downloadSelected}>
            ⬇ {t.photos.downloadAll}
          </button>
          <button
            className="docs-btn"
            disabled={albums.length === 0}
            onClick={() => setAlbumPicker(true)}
          >
            🗂 {t.photos.moveToAlbum}
          </button>
          <button className="docs-btn" onClick={deleteSelected}>
            🗑 {t.photos.deleteSelected}
          </button>
          <button className="link-btn" onClick={exitSelection}>
            {t.photos.selectDone}
          </button>
        </div>
      )}

      {busy && <p className="docs-busy">{busy}</p>}
      {error && <p className="error">{error}</p>}

      {showingAlbums ? (
        albums.length === 0 ? (
          <div className="docs-empty">
            <div className="empty-icon">🗂</div>
            <strong>{t.photos.noAlbums}</strong>
            <p>{t.photos.noAlbumsHint}</p>
          </div>
        ) : (
          <div className="albums-grid">
            {albums.map((album) => {
              const inside = photos.filter((p) =>
                parseAlbumIds(p.albumIdsRaw).includes(album.id)
              );
              const cover = inside.find((p) => p.thumbnailBase64);
              return (
                <div key={album.id} className="album-card">
                  <button className="album-cover" onClick={() => setOpenAlbum(album)}>
                    {cover ? (
                      <img
                        src={`data:image/jpeg;base64,${cover.thumbnailBase64}`}
                        alt={album.title}
                      />
                    ) : (
                      <span className="album-placeholder">🗂</span>
                    )}
                  </button>
                  <div className="album-info">
                    <span className="album-title">{album.title}</span>
                    <span className="album-count">{t.photos.photoCount(inside.length)}</span>
                  </div>
                  <div className="card-actions">
                    <button
                      onClick={() => setRenamingAlbum(album)}
                      title={t.photos.renameAlbum}
                    >
                      ✎
                    </button>
                    <button
                      onClick={async () => {
                        if (!window.confirm(t.photos.deleteAlbumConfirm)) return;
                        await deleteAlbum({
                          familyId: currentFamilyId,
                          userId: user.uid,
                          albumId: album.id,
                          photos,
                        });
                      }}
                      title={t.photos.deleteAlbum}
                    >
                      🗑
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )
      ) : visiblePhotos.length === 0 ? (
        <div className="docs-empty">
          <div className="empty-icon">🖼</div>
          <strong>{t.photos.empty}</strong>
          <p>{t.photos.emptyHint}</p>
        </div>
      ) : grouping === "year" ? (
        /* Un riquadro per anno: una copertina, non tutte le foto. */
        <div className="year-grid">
          {yearSummaries.map((y) => (
            <button key={y.year} className="year-card" onClick={() => openYear(y.year)}>
              {y.cover?.thumbnailBase64 ? (
                <img src={`data:image/jpeg;base64,${y.cover.thumbnailBase64}`} alt="" />
              ) : (
                <span className="album-placeholder">🖼</span>
              )}
              <span className="year-overlay">
                <span className="year-label">{y.year}</span>
                <span className="year-count">{t.photos.photoCount(y.count)}</span>
              </span>
            </button>
          ))}
        </div>
      ) : grouping === "month" ? (
        /* Un riquadro per mese con poche anteprime, non l'intero rullino. */
        <div className="month-cards">
          {monthSummaries.map((m) => (
            <button
              key={`${m.year}-${m.month}`}
              className="month-card"
              onClick={() => openMonth(m.year, m.month)}
            >
              <div className="month-card-head">
                <span className="month-card-title">
                  {monthLabel(m.year, m.month, locale)}
                </span>
                <span className="month-card-count">
                  {t.photos.photoCount(m.items.length)}
                </span>
              </div>
              <div className="month-card-strip">
                {m.items.slice(0, 6).map((p) => (
                  <span key={p.id} className="month-thumb">
                    {p.thumbnailBase64 ? (
                      <img src={`data:image/jpeg;base64,${p.thumbnailBase64}`} alt="" />
                    ) : (
                      <span className="photo-placeholder">🖼</span>
                    )}
                  </span>
                ))}
                {m.items.length > 6 && (
                  <span className="month-more">+{m.items.length - 6}</span>
                )}
              </div>
            </button>
          ))}
        </div>
      ) : (
        /* "Tutto": la libreria intera, o l'insieme scelto navigando. */
        <div className="photo-grid">
          {scopedPhotos.map((p) => (
            <button
              key={p.id}
              className={"photo-cell" + (selected.has(p.id) ? " selected" : "")}
              onClick={() =>
                selectionMode
                  ? toggleSelected(p.id)
                  : setGalleryIndex(scopedPhotos.findIndex((x) => x.id === p.id))
              }
              title={p.caption || p.fileName}
            >
              {selectionMode && (
                <span className="photo-tick">{selected.has(p.id) ? "✅" : "⚪️"}</span>
              )}
              {p.thumbnailBase64 ? (
                <img
                  src={`data:image/jpeg;base64,${p.thumbnailBase64}`}
                  alt={p.caption || p.fileName}
                  loading="lazy"
                />
              ) : (
                <span className="photo-placeholder">
                  {(p.mimeType ?? "").startsWith("video/") ? "🎬" : "🖼"}
                </span>
              )}
              {(p.mimeType ?? "").startsWith("video/") && (
                <span className="photo-badge">
                  ▶ {formatDuration(p.videoDurationSeconds) ?? ""}
                </span>
              )}
            </button>
          ))}
        </div>
      )}

      {galleryIndex !== null && (
        <PhotoGallery
          photos={scopedPhotos}
          startIndex={galleryIndex}
          albums={albums}
          familyId={currentFamilyId}
          userId={user.uid}
          onClose={() => setGalleryIndex(null)}
        />
      )}

      {albumPicker && (
        <Modal onClose={() => setAlbumPicker(false)}>
          <div className="modal-header">
            <button className="modal-icon-btn" onClick={() => setAlbumPicker(false)}>
              ✕
            </button>
          </div>
          <div className="modal-title">{t.photos.pickAlbum}</div>
          <div className="modal-section">
            {albums.map((a) => (
              <button
                key={a.id}
                className="modal-option"
                onClick={() => moveSelectedToAlbum(a.id)}
              >
                🗂 {a.title}
              </button>
            ))}
          </div>
        </Modal>
      )}

      {newAlbumOpen && (
        <NamePrompt
          title={t.photos.newAlbum}
          placeholder={t.photos.albumName}
          onCancel={() => setNewAlbumOpen(false)}
          onSave={async (title) => {
            await createAlbum({ familyId: currentFamilyId, userId: user.uid, title });
            setNewAlbumOpen(false);
          }}
        />
      )}

      {renamingAlbum && (
        <NamePrompt
          title={t.photos.renameAlbum}
          placeholder={t.photos.albumName}
          initial={renamingAlbum.title}
          onCancel={() => setRenamingAlbum(null)}
          onSave={async (title) => {
            await renameAlbum({
              familyId: currentFamilyId,
              userId: user.uid,
              albumId: renamingAlbum.id,
              title,
            });
            setRenamingAlbum(null);
          }}
        />
      )}
    </div>
  );
}

function NamePrompt({ title, placeholder, initial = "", onCancel, onSave }) {
  const { t } = useTranslation();
  const [value, setValue] = useState(initial);

  const submit = () => {
    const name = value.trim();
    if (name) onSave(name);
  };

  return (
    <Modal onClose={onCancel}>
      <div className="modal-header">
        <button className="modal-text-btn" onClick={onCancel}>
          {t.photos.cancel}
        </button>
        <button className="modal-save-btn" disabled={!value.trim()} onClick={submit}>
          {t.photos.save}
        </button>
      </div>
      <div className="modal-title">{title}</div>
      <input
        className="modal-field"
        placeholder={placeholder}
        value={value}
        autoFocus
        onChange={(e) => setValue(e.target.value)}
        onKeyDown={(e) => e.key === "Enter" && submit()}
      />
    </Modal>
  );
}
