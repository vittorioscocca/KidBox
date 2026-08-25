import { useRef, useState } from "react";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import { setHeroPhoto } from "../services/familyHeroPhoto";
import "./Home.css";

export default function Home() {
  const { currentFamily, currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();
  const fileInputRef = useRef(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const dateLabel = new Date().toLocaleDateString(locale === "en" ? "en-US" : "it-IT", {
    weekday: "long",
    day: "numeric",
    month: "long",
  });

  const heroUrl = currentFamily?.heroPhotoURL || null;
  // Stessi campi e stesso ordine di trasformazione dei client nativi: la scala è
  // applicata prima, la traslazione è in pixel (Compose graphicsLayer / SwiftUI).
  const heroStyle = heroUrl
    ? {
        backgroundImage: `url(${heroUrl})`,
        transform: `translate(${currentFamily?.heroPhotoOffsetX ?? 0}px, ${
          currentFamily?.heroPhotoOffsetY ?? 0
        }px) scale(${currentFamily?.heroPhotoScale ?? 1})`,
      }
    : null;

  const onPickFile = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = ""; // permette di riselezionare lo stesso file
    if (!file) return;
    setBusy(true);
    setError(null);
    try {
      await setHeroPhoto({
        familyId: currentFamilyId,
        file,
        uid: user.uid,
        // Il crop già impostato da un altro client non va perso.
        crop: {
          scale: currentFamily?.heroPhotoScale ?? 1,
          offsetX: currentFamily?.heroPhotoOffsetX ?? 0,
          offsetY: currentFamily?.heroPhotoOffsetY ?? 0,
        },
      });
    } catch (err) {
      setError(`${t.home.uploadFailed}: ${err.message}`);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div>
      <h1>{t.home.title}</h1>

      <div className="hero-card">
        {heroStyle ? (
          <div className="hero-photo" style={heroStyle} />
        ) : (
          <div className="hero-photo hero-photo-empty" />
        )}
        <div className="hero-scrim" />

        <div className="hero-top">
          <span className="hero-date">{dateLabel}</span>
          <span className="hero-badge">
            {t.home.membersCount(currentFamily?.memberCount ?? 0)}
          </span>
        </div>

        <div className="hero-bottom">
          <div className="hero-title">{currentFamily?.name || "…"}</div>
          <button
            className="hero-change-btn"
            disabled={busy || !currentFamilyId}
            onClick={() => fileInputRef.current?.click()}
          >
            🖼 {busy ? t.home.uploading : t.home.changePhoto}
          </button>
        </div>

        <input
          ref={fileInputRef}
          type="file"
          accept="image/*"
          hidden
          onChange={onPickFile}
        />
      </div>

      {error && <p className="error">{error}</p>}
      <p className="hint">{t.home.pickSection}</p>
    </div>
  );
}
