import { useTranslation } from "../i18n/LocaleContext";
import "./DocumentViewer.css";

/**
 * Anteprima a schermo del documento già decifrato.
 *
 * L'URL è un blob: locale creato dopo la decifratura, non l'URL di Storage — il
 * file su Storage è cifrato e il browser non saprebbe cosa farsene.
 */
export default function DocumentViewer({ document: docData, url, onDownload, onClose }) {
  const { t } = useTranslation();
  const mime = docData.mimeType || "";

  const body = () => {
    if (mime.startsWith("image/")) {
      return <img src={url} alt={docData.title || docData.fileName} />;
    }
    if (mime === "application/pdf") {
      return <iframe src={url} title={docData.title || docData.fileName} />;
    }
    if (mime.startsWith("video/")) {
      return <video src={url} controls />;
    }
    if (mime.startsWith("audio/")) {
      return <audio src={url} controls />;
    }
    // Tipi che il browser non sa mostrare (docx, xlsx, zip…): resta il download.
    return (
      <div className="viewer-fallback">
        <div className="viewer-fallback-icon">📄</div>
        <p>{t.documents.previewUnavailable}</p>
        <button className="docs-btn" onClick={onDownload}>
          ⬇ {t.documents.download}
        </button>
      </div>
    );
  };

  return (
    <div className="viewer-overlay" onClick={onClose}>
      <div className="viewer-panel" onClick={(e) => e.stopPropagation()}>
        <div className="viewer-bar">
          <span className="viewer-title">{docData.title || docData.fileName}</span>
          <div className="viewer-actions">
            <button onClick={onDownload} title={t.documents.download}>
              ⬇
            </button>
            <button onClick={onClose} title={t.documents.cancel}>
              ✕
            </button>
          </div>
        </div>
        <div className="viewer-body">{body()}</div>
      </div>
    </div>
  );
}
