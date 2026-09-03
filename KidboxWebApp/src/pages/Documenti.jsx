import { useEffect, useMemo, useRef, useState } from "react";
import { collection, onSnapshot, query, where } from "firebase/firestore";
import { db } from "../firebase";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import { MissingFamilyKeyError, loadFamilyKey } from "../services/familyKey";
import {
  createFolder,
  deleteFolderRecursive,
  fetchDocumentBlob,
  moveDocument,
  renameDocument,
  renameFolder,
  shareDocuments,
  softDeleteDocument,
  uploadDocument,
} from "../services/documents";
import { imagesToPdf, isConvertibleImage, mergePdfs, unlockPdf } from "../services/pdfTools";
import DocumentViewer from "../components/DocumentViewer";
import Modal from "../components/Modal";
import "./Documenti.css";

/** Da una sola immagine si eredita il nome; da più si dice quante sono. */
function defaultPdfNameFor(images) {
  const first = images[0];
  if (!first) return "Documento";
  const base = (first.title || first.fileName || "Documento").replace(/\.[^.]+$/, "");
  return images.length === 1 ? base : `${base} (+${images.length - 1})`;
}

function formatSize(bytes) {
  if (!bytes) return "";
  const units = ["B", "KB", "MB", "GB"];
  let value = Number(bytes);
  let i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i += 1;
  }
  return `${value.toFixed(value < 10 && i > 0 ? 1 : 0)} ${units[i]}`;
}

function fileIcon(mime = "") {
  if (mime.startsWith("image/")) return "🖼";
  if (mime === "application/pdf") return "📕";
  if (mime.includes("word")) return "📘";
  if (mime.includes("sheet") || mime.includes("excel")) return "📗";
  if (mime.startsWith("video/")) return "🎬";
  if (mime.startsWith("audio/")) return "🎵";
  return "📄";
}

export default function Documenti() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();

  const [keyError, setKeyError] = useState(null);
  const [folders, setFolders] = useState([]);
  const [documents, setDocuments] = useState([]);
  const [path, setPath] = useState([]); // stack di cartelle: [] = radice
  const [search, setSearch] = useState("");
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(null);
  const [viewing, setViewing] = useState(null);
  const [renaming, setRenaming] = useState(null); // {kind:'doc'|'folder', item}
  const [movingDoc, setMovingDoc] = useState(null);
  const [newFolderOpen, setNewFolderOpen] = useState(false);
  const [dragging, setDragging] = useState(false);
  /** Cartella sotto il puntatore durante il trascinamento; null = quella aperta. */
  const [dropFolder, setDropFolder] = useState(null);
  const [view, setView] = useState(
    () => localStorage.getItem("kidbox:docsView") || "list"
  );
  const [selectionMode, setSelectionMode] = useState(false);
  const [selected, setSelected] = useState(() => new Set());
  const [merging, setMerging] = useState(false);
  const [convertingImages, setConvertingImages] = useState(false);
  const [unlocking, setUnlocking] = useState(null);
  const [notice, setNotice] = useState(null);
  const fileInput = useRef(null);
  /**
   * Profondità del trascinamento. `dragleave` risale anche quando il puntatore
   * passa da un figlio all'altro: contando entrate e uscite l'evidenziazione
   * non sfarfalla mentre si attraversa la lista.
   */
  const dragDepth = useRef(0);

  const currentFolderId = path.length ? path[path.length - 1].id : null;

  // La chiave serve per cifrare/decifrare: se manca, la sezione non è usabile.
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
      collection(db, "families", currentFamilyId, "documentCategories"),
      where("isDeleted", "==", false)
    );
    return onSnapshot(
      q,
      (snap) => setFolders(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (err) => setError(err.message)
    );
  }, [currentFamilyId]);

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    const q = query(
      collection(db, "families", currentFamilyId, "documents"),
      where("isDeleted", "==", false)
    );
    return onSnapshot(
      q,
      (snap) => setDocuments(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (err) => setError(err.message)
    );
  }, [currentFamilyId]);

  const searching = search.trim().length > 0;

  const visibleFolders = useMemo(() => {
    if (searching) return [];
    return folders
      .filter((f) => (f.parentId ?? null) === currentFolderId)
      .sort((a, b) => (a.title ?? "").localeCompare(b.title ?? ""));
  }, [folders, currentFolderId, searching]);

  const visibleDocs = useMemo(() => {
    const q = search.trim().toLowerCase();
    // La ricerca guarda in tutte le cartelle, non solo in quella aperta.
    const base = searching
      ? documents.filter(
          (d) =>
            (d.title ?? "").toLowerCase().includes(q) ||
            (d.fileName ?? "").toLowerCase().includes(q)
        )
      : documents.filter((d) => (d.categoryId ?? null) === currentFolderId);
    return base.sort(
      (a, b) => (b.updatedAt?.toMillis?.() ?? 0) - (a.updatedAt?.toMillis?.() ?? 0)
    );
  }, [documents, currentFolderId, search, searching]);

  const handleFiles = async (fileList, targetFolderId = currentFolderId) => {
    const files = [...fileList];
    if (!files.length) return;
    setError(null);
    setBusy(t.documents.uploading(files.length));
    try {
      // Sequenziale: cifratura e upload in parallelo su file grandi
      // saturerebbero memoria e banda.
      for (const file of files) {
        await uploadDocument({
          familyId: currentFamilyId,
          userId: user.uid,
          file,
          categoryId: targetFolderId,
        });
      }
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  const openDocument = async (docData) => {
    setError(null);
    setBusy(t.documents.loading);
    try {
      const blob = await fetchDocumentBlob({
        familyId: currentFamilyId,
        userId: user.uid,
        document: docData,
      });
      setViewing({ doc: docData, url: URL.createObjectURL(blob), blob });
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  const downloadDocument = async (docData) => {
    setBusy(t.documents.loading);
    try {
      const blob = await fetchDocumentBlob({
        familyId: currentFamilyId,
        userId: user.uid,
        document: docData,
      });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = docData.fileName || docData.title || "documento";
      a.click();
      URL.revokeObjectURL(url);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  const setViewMode = (mode) => {
    localStorage.setItem("kidbox:docsView", mode);
    setView(mode);
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

  const selectedDocs = visibleDocs.filter((d) => selected.has(d.id));
  const selectedPdfs = selectedDocs.filter((d) => d.mimeType === "application/pdf");
  const selectedImages = selectedDocs.filter(isConvertibleImage);
  /** Il pulsante compare solo se la selezione è fatta di sole immagini. */
  const canConvertImages =
    selectedImages.length > 0 && selectedImages.length === selectedDocs.length;

  const shareSelected = async () => {
    setError(null);
    setBusy(t.documents.working);
    try {
      const result = await shareDocuments({
        familyId: currentFamilyId,
        userId: user.uid,
        documents: selectedDocs.length ? selectedDocs : [],
      });
      if (result === "downloaded") setNotice(t.documents.sharedDownloaded);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  const doMerge = async (title) => {
    setError(null);
    setBusy(t.documents.working);
    try {
      // L'ordine di unione è quello mostrato a schermo, come su iOS.
      const buffers = [];
      for (const d of selectedPdfs) {
        const blob = await fetchDocumentBlob({
          familyId: currentFamilyId,
          userId: user.uid,
          document: d,
        });
        buffers.push(await blob.arrayBuffer());
      }
      const merged = await mergePdfs(buffers);
      await uploadDocument({
        familyId: currentFamilyId,
        userId: user.uid,
        bytes: merged,
        name: `${title}.pdf`,
        mimeType: "application/pdf",
        categoryId: currentFolderId,
      });
      setSelected(new Set());
      setMerging(false);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  const doConvertToPdf = async (title) => {
    setError(null);
    setBusy(t.documents.working);
    try {
      // Stesso ordine mostrato a schermo, come su iOS e Android.
      const images = [];
      for (const d of selectedImages) {
        const blob = await fetchDocumentBlob({
          familyId: currentFamilyId,
          userId: user.uid,
          document: d,
        });
        images.push({
          bytes: await blob.arrayBuffer(),
          mimeType: d.mimeType,
          name: d.title || d.fileName,
        });
      }
      const pdfBytes = await imagesToPdf(images);
      await uploadDocument({
        familyId: currentFamilyId,
        userId: user.uid,
        bytes: pdfBytes,
        name: `${title}.pdf`,
        mimeType: "application/pdf",
        categoryId: currentFolderId,
      });
      setSelected(new Set());
      setConvertingImages(false);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  const doUnlock = async ({ password, title }) => {
    setError(null);
    setBusy(t.documents.working);
    try {
      const blob = await fetchDocumentBlob({
        familyId: currentFamilyId,
        userId: user.uid,
        document: unlocking,
      });
      const { bytes, rasterized } = await unlockPdf(await blob.arrayBuffer(), password);
      await uploadDocument({
        familyId: currentFamilyId,
        userId: user.uid,
        bytes,
        name: `${title}.pdf`,
        mimeType: "application/pdf",
        categoryId: currentFolderId,
      });
      if (rasterized) setNotice(t.documents.unlockRasterHint);
      setUnlocking(null);
    } catch (err) {
      setError(err.code === "wrong-password" ? t.documents.unlockWrong : err.message);
    } finally {
      setBusy(null);
    }
  };

  const removeDocument = async (docData) => {
    if (!window.confirm(t.documents.deleteConfirm)) return;
    await softDeleteDocument({
      familyId: currentFamilyId,
      userId: user.uid,
      documentId: docData.id,
    });
  };

  /* ── Trascinamento file ──────────────────────────────────────────────── */

  /** Solo i file: trascinando testo o un link non deve accendersi niente. */
  const hasFiles = (e) => Array.from(e.dataTransfer?.types ?? []).includes("Files");

  const onDragEnter = (e) => {
    if (!hasFiles(e)) return;
    dragDepth.current += 1;
    setDragging(true);
  };

  const onDragLeave = () => {
    dragDepth.current = Math.max(dragDepth.current - 1, 0);
    if (dragDepth.current === 0) {
      setDragging(false);
      setDropFolder(null);
    }
  };

  const onDragOver = (e) => {
    if (!hasFiles(e)) return;
    // Senza `preventDefault` il browser apre il file invece di lasciarlo cadere.
    e.preventDefault();
    e.dataTransfer.dropEffect = "copy";
  };

  const onDrop = (e) => {
    if (!hasFiles(e)) return;
    e.preventDefault();
    // La cartella sotto il puntatore vince sulla cartella aperta: così si carica
    // dentro una sottocartella senza doverci prima entrare.
    const target = dropFolder ? dropFolder.id : currentFolderId;
    dragDepth.current = 0;
    setDragging(false);
    setDropFolder(null);
    handleFiles(e.dataTransfer.files, target);
  };

  const dropTargetName = dropFolder
    ? dropFolder.title
    : path.length
      ? path[path.length - 1].title
      : t.documents.root;

  const removeFolder = async (folder) => {
    const inside =
      documents.filter((d) => d.categoryId === folder.id).length +
      folders.filter((f) => f.parentId === folder.id).length;
    if (!window.confirm(t.documents.deleteFolderConfirm(inside))) return;
    await deleteFolderRecursive({
      familyId: currentFamilyId,
      userId: user.uid,
      folderId: folder.id,
      allFolders: folders,
      allDocuments: documents,
    });
  };

  if (keyError === "missing") {
    return (
      <div className="notes-locked">
        <div className="locked-icon">🔒</div>
        <h2>{t.documents.keyMissing}</h2>
        <p>{t.documents.keyMissingHint}</p>
      </div>
    );
  }

  return (
    <div
      className={"docs-page" + (dragging ? " drag-over" : "")}
      onDragEnter={onDragEnter}
      onDragOver={onDragOver}
      onDragLeave={onDragLeave}
      onDrop={onDrop}
    >
      {dragging && (
        <div className="docs-drop-hint">{t.documents.dropInto(dropTargetName)}</div>
      )}
      <div className="docs-toolbar">
        <button className="toolbar-add" onClick={() => fileInput.current?.click()}>
          ⬆
        </button>
        <button className="docs-btn" onClick={() => setNewFolderOpen(true)}>
          📁 {t.documents.newFolder}
        </button>
        <div className="toolbar-search">
          <span className="search-icon">🔍</span>
          <input
            placeholder={t.documents.search}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          {search && (
            <button className="search-clear" onClick={() => setSearch("")}>
              ✕
            </button>
          )}
        </div>
        <button
          className={"docs-btn" + (selectionMode ? " active" : "")}
          onClick={() => (selectionMode ? exitSelection() : setSelectionMode(true))}
        >
          {selectionMode ? `✓ ${t.documents.selectDone}` : `☑ ${t.documents.select}`}
        </button>
        <div className="view-toggle">
          <button
            className={view === "list" ? "active" : ""}
            onClick={() => setViewMode("list")}
            title={t.documents.viewList}
          >
            ☰
          </button>
          <button
            className={view === "grid" ? "active" : ""}
            onClick={() => setViewMode("grid")}
            title={t.documents.viewGrid}
          >
            ▦
          </button>
        </div>
        <input
          ref={fileInput}
          type="file"
          multiple
          hidden
          onChange={(e) => {
            handleFiles(e.target.files);
            e.target.value = "";
          }}
        />
      </div>

      <div className="docs-breadcrumb">
        <button onClick={() => setPath([])}>{t.documents.root}</button>
        {path.map((folder, i) => (
          <span key={folder.id}>
            <span className="crumb-sep">›</span>
            <button onClick={() => setPath(path.slice(0, i + 1))}>{folder.title}</button>
          </span>
        ))}
      </div>

      {selectionMode && selected.size > 0 && (
        <div className="selection-bar">
          <span>{t.documents.selected(selected.size)}</span>
          <button className="docs-btn" onClick={shareSelected}>
            ↗ {t.documents.share}
          </button>
          <button
            className="docs-btn"
            disabled={selectedPdfs.length < 2}
            title={selectedPdfs.length < 2 ? t.documents.mergeNeedsTwo : undefined}
            onClick={() => setMerging(true)}
          >
            ⧉ {t.documents.merge}
          </button>
          {canConvertImages && (
            <button className="docs-btn" onClick={() => setConvertingImages(true)}>
              🖼 {t.documents.toPdf}
            </button>
          )}
          <button className="link-btn" onClick={exitSelection}>
            {t.documents.clearSelection}
          </button>
        </div>
      )}

      {busy && <p className="docs-busy">{busy}</p>}
      {error && <p className="error">{error}</p>}
      {notice && (
        <p className="docs-notice">
          {notice}
          <button className="link-btn" onClick={() => setNotice(null)}>✕</button>
        </p>
      )}

      {visibleFolders.length > 0 && (
        <>
          <h3 className="docs-section">{t.documents.folders}</h3>
          <ul className={view === "grid" ? "docs-grid" : "docs-list"}>
            {visibleFolders.map((folder) => (
              <li
                key={folder.id}
                className={
                  "folder-card" + (dropFolder?.id === folder.id ? " drop-target" : "")
                }
                onDoubleClick={() => setPath([...path, folder])}
                onDragEnter={() => setDropFolder(folder)}
                // Passando da una cartella all'altra l'entrata precede l'uscita:
                // senza questo controllo la nuova destinazione verrebbe subito
                // cancellata da chi esce.
                onDragLeave={() =>
                  setDropFolder((current) => (current?.id === folder.id ? null : current))
                }
              >
                <span className="folder-icon">📁</span>
                <button
                  className="folder-main"
                  onClick={() => setPath([...path, folder])}
                >
                  <span className="folder-name">{folder.title}</span>
                </button>
                <div className="card-actions">
                  <button
                    onClick={() => setRenaming({ kind: "folder", item: folder })}
                    title={t.documents.rename}
                  >
                    ✎
                  </button>
                  <button onClick={() => removeFolder(folder)} title={t.documents.delete}>
                    🗑
                  </button>
                </div>
              </li>
            ))}
          </ul>
        </>
      )}

      <h3 className="docs-section">{t.documents.files}</h3>
      {visibleDocs.length === 0 ? (
        <div className="docs-empty">
          <div className="empty-icon">{searching ? "🔍" : "📂"}</div>
          <strong>{searching ? t.documents.noResults : t.documents.empty}</strong>
          {!searching && <p>{t.documents.emptyHint}</p>}
        </div>
      ) : (
        <ul className={view === "grid" ? "docs-filegrid" : "docs-list"}>
          {visibleDocs.map((d) => (
            <li key={d.id} className={selected.has(d.id) ? "selected" : ""}>
              {selectionMode && (
                <input
                  type="checkbox"
                  className="doc-check"
                  checked={selected.has(d.id)}
                  onChange={() => toggleSelected(d.id)}
                />
              )}
              <span className="doc-icon">{fileIcon(d.mimeType)}</span>
              <button
                className="doc-main"
                onClick={() =>
                  selectionMode ? toggleSelected(d.id) : openDocument(d)
                }
              >
                <span className="doc-title">{d.title || d.fileName}</span>
                <span className="doc-meta">
                  {formatSize(d.fileSize)}
                  {d.updatedAt?.toDate?.() &&
                    ` · ${new Intl.DateTimeFormat(
                      locale === "en" ? "en-US" : "it-IT",
                      { day: "2-digit", month: "2-digit", year: "2-digit" }
                    ).format(d.updatedAt.toDate())}`}
                </span>
              </button>
              <div className="doc-actions">
                <button onClick={() => downloadDocument(d)} title={t.documents.download}>
                  ⬇
                </button>
                {d.mimeType === "application/pdf" && (
                  <button onClick={() => setUnlocking(d)} title={t.documents.unlock}>
                    🔓
                  </button>
                )}
                <button
                  onClick={() => setRenaming({ kind: "doc", item: d })}
                  title={t.documents.rename}
                >
                  ✎
                </button>
                <button onClick={() => setMovingDoc(d)} title={t.documents.move}>
                  📂
                </button>
                <button onClick={() => removeDocument(d)} title={t.documents.delete}>
                  🗑
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}

      {viewing && (
        <DocumentViewer
          document={viewing.doc}
          url={viewing.url}
          onDownload={() => downloadDocument(viewing.doc)}
          onClose={() => {
            URL.revokeObjectURL(viewing.url);
            setViewing(null);
          }}
        />
      )}

      {newFolderOpen && (
        <NameModal
          title={t.documents.newFolder}
          placeholder={t.documents.folderName}
          onCancel={() => setNewFolderOpen(false)}
          onSave={async (name) => {
            await createFolder({
              familyId: currentFamilyId,
              userId: user.uid,
              title: name,
              parentId: currentFolderId,
            });
            setNewFolderOpen(false);
          }}
        />
      )}

      {renaming && (
        <NameModal
          title={t.documents.rename}
          placeholder={t.documents.newTitle}
          initial={renaming.item.title ?? ""}
          onCancel={() => setRenaming(null)}
          onSave={async (name) => {
            if (renaming.kind === "folder") {
              await renameFolder({
                familyId: currentFamilyId,
                userId: user.uid,
                folderId: renaming.item.id,
                title: name,
              });
            } else {
              await renameDocument({
                familyId: currentFamilyId,
                userId: user.uid,
                documentId: renaming.item.id,
                title: name,
              });
            }
            setRenaming(null);
          }}
        />
      )}

      {merging && (
        <NameModal
          title={t.documents.merge}
          placeholder={t.documents.mergeTitle}
          initial="Unione"
          onCancel={() => setMerging(false)}
          onSave={doMerge}
        />
      )}

      {convertingImages && (
        <NameModal
          title={t.documents.toPdfTitle}
          placeholder={t.documents.toPdfName}
          initial={defaultPdfNameFor(selectedImages)}
          onCancel={() => setConvertingImages(false)}
          onSave={doConvertToPdf}
        />
      )}

      {unlocking && (
        <UnlockModal
          document={unlocking}
          onCancel={() => setUnlocking(null)}
          onSubmit={doUnlock}
        />
      )}

      {movingDoc && (
        <Modal onClose={() => setMovingDoc(null)}>
          <div className="modal-header">
            <button className="modal-icon-btn" onClick={() => setMovingDoc(null)}>
              ✕
            </button>
          </div>
          <div className="modal-title">{t.documents.moveTo}</div>
          <div className="modal-section">
            <button
              className="modal-option"
              onClick={async () => {
                await moveDocument({
                  familyId: currentFamilyId,
                  userId: user.uid,
                  documentId: movingDoc.id,
                  categoryId: null,
                });
                setMovingDoc(null);
              }}
            >
              📂 {t.documents.root}
              {!movingDoc.categoryId && " ✓"}
            </button>
            {folders.map((f) => (
              <button
                key={f.id}
                className="modal-option"
                onClick={async () => {
                  await moveDocument({
                    familyId: currentFamilyId,
                    userId: user.uid,
                    documentId: movingDoc.id,
                    categoryId: f.id,
                  });
                  setMovingDoc(null);
                }}
              >
                📁 {f.title}
                {movingDoc.categoryId === f.id && " ✓"}
              </button>
            ))}
          </div>
        </Modal>
      )}
    </div>
  );
}

function UnlockModal({ document: docData, onCancel, onSubmit }) {
  const { t } = useTranslation();
  const [password, setPassword] = useState("");
  const [title, setTitle] = useState(
    (docData.title || docData.fileName || "documento").replace(/\.pdf$/i, "") + " (sbloccato)"
  );

  return (
    <Modal onClose={onCancel}>
      <div className="modal-header">
        <button className="modal-text-btn" onClick={onCancel}>
          {t.documents.cancel}
        </button>
        <button
          className="modal-save-btn"
          disabled={!password || !title.trim()}
          onClick={() => onSubmit({ password, title: title.trim() })}
        >
          {t.documents.save}
        </button>
      </div>
      <div className="modal-title">{t.documents.unlock}</div>
      <input
        className="modal-field"
        type="password"
        placeholder={t.documents.unlockPassword}
        value={password}
        autoFocus
        onChange={(e) => setPassword(e.target.value)}
      />
      <input
        className="modal-field"
        placeholder={t.documents.unlockTitle}
        value={title}
        onChange={(e) => setTitle(e.target.value)}
      />
    </Modal>
  );
}

function NameModal({ title, placeholder, initial = "", onCancel, onSave }) {
  const { t } = useTranslation();
  const [value, setValue] = useState(initial);
  const [saving, setSaving] = useState(false);

  const submit = async () => {
    const name = value.trim();
    if (!name || saving) return;
    setSaving(true);
    await onSave(name);
  };

  return (
    <Modal onClose={onCancel}>
      <div className="modal-header">
        <button className="modal-text-btn" onClick={onCancel}>
          {t.documents.cancel}
        </button>
        <button className="modal-save-btn" disabled={!value.trim() || saving} onClick={submit}>
          {t.documents.save}
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
