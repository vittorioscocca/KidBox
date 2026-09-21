/**
 * Allegati di una scheda di Salute (visita, esame, cura) — porting delle
 * sezioni `*AttachmentsSection` di iOS.
 *
 * Come sul telefono ogni allegato è un documento in `Documenti › Salute ›
 * Referti` marcato con il tag della scheda; qui si apre nel browser, si
 * scarica, si aggiunge e si toglie. La lista arriva dal listener unico di
 * `Salute.jsx`, che ascolta i tre prefissi insieme.
 */
import { useRef, useState } from "react";
import {
  fetchDocumentBlob,
  softDeleteDocument,
  uploadDocument,
} from "../../services/documents";
import { ensureHealthFolders } from "../../services/attachments";

const sizeLabel = (bytes) => {
  if (!bytes) return "";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
};

const mimeIcon = (mime = "") => {
  if (mime.includes("pdf")) return "📄";
  if (mime.includes("image")) return "🖼️";
  return "📎";
};

export default function HealthAttachments({
  familyId,
  userId,
  childId,
  tag,
  attachments,
  h,
  onError,
}) {
  const a = h.attachments;
  const fileRef = useRef(null);
  const [busy, setBusy] = useState(false);
  const items = attachments?.get(tag) || [];

  const fetchBlob = (docData) =>
    fetchDocumentBlob({ familyId, userId, document: docData });

  const open = async (docData) => {
    try {
      const blob = await fetchBlob(docData);
      window.open(URL.createObjectURL(blob), "_blank", "noopener");
    } catch (err) {
      onError(err);
    }
  };

  const download = async (docData) => {
    try {
      const blob = await fetchBlob(docData);
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = docData.fileName || docData.title || "documento";
      link.click();
      URL.revokeObjectURL(url);
    } catch (err) {
      onError(err);
    }
  };

  const remove = async (docData) => {
    if (!window.confirm(a.confirmDelete)) return;
    try {
      await softDeleteDocument({ familyId, userId, documentId: docData.id });
    } catch (err) {
      onError(err);
    }
  };

  const upload = async (file) => {
    if (!file) return;
    setBusy(true);
    try {
      const { referti } = await ensureHealthFolders({ familyId, userId });
      await uploadDocument({
        familyId,
        userId,
        file,
        categoryId: referti.id,
        notes: tag,
        childId,
      });
    } catch (err) {
      onError(err);
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="sa-attachments">
      <h3 className="sa-attachments-title">📎 {a.title}</h3>

      {items.length === 0 ? (
        <p className="sa-attachments-empty">{a.empty}</p>
      ) : (
        <ul className="sa-attachment-list">
          {items.map((d) => (
            <li key={d.id} className="sa-attachment">
              <span className="sa-attachment-icon">{mimeIcon(d.mimeType)}</span>
              <span className="sa-attachment-body">
                <span className="sa-attachment-name">{d.title || d.fileName}</span>
                <span className="sa-attachment-meta">{sizeLabel(d.fileSize)}</span>
              </span>
              <span className="sa-attachment-actions">
                <button onClick={() => open(d)} title={a.open}>
                  👁
                </button>
                <button onClick={() => download(d)} title={a.download}>
                  ⬇
                </button>
                <button className="pw-danger" onClick={() => remove(d)} title={a.remove}>
                  ✕
                </button>
              </span>
            </li>
          ))}
        </ul>
      )}

      <button
        className="sa-attachment-add"
        disabled={busy}
        onClick={() => fileRef.current?.click()}
      >
        + {busy ? a.uploading : a.add}
      </button>
      <input
        ref={fileRef}
        type="file"
        hidden
        onChange={(e) => {
          upload(e.target.files?.[0]);
          e.target.value = "";
        }}
      />

      <p className="sa-attachments-hint">{a.hint}</p>
    </section>
  );
}
