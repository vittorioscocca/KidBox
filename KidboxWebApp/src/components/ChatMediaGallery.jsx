/**
 * «Media, link e documenti»: porta sul web `ChatMediaGalleryView` (iOS).
 *
 * Rilegge la conversazione dall'inizio invece di usare solo i messaggi già a
 * schermo: la galleria serve proprio a ritrovare la foto di tre mesi fa, e una
 * galleria che mostra solo l'ultima pagina non risponderebbe a quella domanda.
 */
import { useEffect, useState } from "react";
import { collection, getDocs, orderBy, query } from "firebase/firestore";
import { db } from "../firebase";
import { decryptString } from "../services/noteCrypto";
import Modal from "./Modal";

const URL_RE = /(https?:\/\/[^\s]+)/g;

export default function ChatMediaGallery({ familyId, familyKey, labels, onClose, onGoToMessage }) {
  const [tab, setTab] = useState("media");
  const [items, setItems] = useState(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const snap = await getDocs(
        query(collection(db, "families", familyId, "chatMessages"), orderBy("createdAt", "desc"))
      );
      const media = [];
      const links = [];
      const documents = [];

      for (const d of snap.docs) {
        const data = d.data();
        if (data.isDeleted) continue;
        const type = data.type || "text";

        if (type === "photo" || type === "video") {
          media.push({ id: d.id, url: data.mediaURL, type });
        } else if (type === "mediaGroup") {
          const urls = JSON.parse(data.mediaGroupURLsJSON || "[]");
          const types = JSON.parse(data.mediaGroupTypesJSON || "[]");
          urls.forEach((url, i) => media.push({ id: d.id, url, type: types[i] || "photo" }));
        } else if (type === "document") {
          let name = data.text || "";
          if (data.textEnc && familyKey) {
            try {
              name = await decryptString(data.textEnc, familyKey);
            } catch {
              /* nome cifrato illeggibile: resta il fallback */
            }
          }
          documents.push({ id: d.id, url: data.mediaURL, name: name || labels.document });
        } else if (type === "text" && familyKey && data.textEnc) {
          try {
            const text = await decryptString(data.textEnc, familyKey);
            for (const url of text.match(URL_RE) || []) links.push({ id: d.id, url });
          } catch {
            /* messaggio non decifrabile: non contribuisce ai link */
          }
        }
      }

      if (!cancelled) setItems({ media, links, documents });
    })();
    return () => {
      cancelled = true;
    };
  }, [familyId, familyKey, labels.document]);

  const current = items?.[tab] ?? [];

  return (
    <Modal onClose={onClose}>
      <div className="modal-header">
        <strong>{labels.galleryTitle}</strong>
        <button className="modal-icon-btn" onClick={onClose}>✕</button>
      </div>

      <div className="chat-gallery-tabs">
        {["media", "links", "documents"].map((key) => (
          <button
            key={key}
            className={tab === key ? "selected" : ""}
            onClick={() => setTab(key)}
          >
            {labels[key]}
          </button>
        ))}
      </div>

      {!items && <p className="pw-hint">{labels.loading}</p>}
      {items && current.length === 0 && <p className="pw-hint">{labels.galleryEmpty}</p>}

      {tab === "media" && (
        <div className="chat-gallery-grid">
          {current.map((item, i) => (
            <button key={`${item.id}-${i}`} onClick={() => onGoToMessage(item.id)}>
              {item.type === "video" ? (
                <video src={item.url} preload="metadata" />
              ) : (
                <img src={item.url} alt="" />
              )}
            </button>
          ))}
        </div>
      )}

      {tab !== "media" &&
        current.map((item, i) => (
          <div className="chat-gallery-row" key={`${item.id}-${i}`}>
            <a href={item.url} target="_blank" rel="noreferrer">
              {tab === "documents" ? `📄 ${item.name}` : `🔗 ${item.url}`}
            </a>
            <button className="link-btn" onClick={() => onGoToMessage(item.id)}>
              {labels.goToMessage}
            </button>
          </div>
        ))}
    </Modal>
  );
}
