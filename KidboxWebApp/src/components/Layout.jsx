import { useEffect, useState } from "react";
import { Outlet, useLocation } from "react-router-dom";
import Sidebar from "./Sidebar";
import AIFab from "./AIFab";
import Assistente from "../pages/Assistente";
import { useTranslation } from "../i18n/LocaleContext";
import { featureFirstUse, screenView, trackAppOpen } from "../services/analytics";
import "./Layout.css";

/**
 * Nome della schermata e feature per GA4.
 *
 * Il vocabolario delle feature NON è libero: sono gli stessi valori che i client
 * nativi passano a `feature_first_use` e `content_created`. Inventarne di nuovi
 * qui creerebbe serie separate che nessun rapporto somma.
 */
const SCREENS = {
  "/": { screen: "home", feature: null },
  "/calendario": { screen: "calendario", feature: "calendar" },
  "/todo": { screen: "todo", feature: null },
  "/note": { screen: "note", feature: "notes" },
  "/spesa": { screen: "spesa", feature: "grocery" },
  "/foto": { screen: "foto", feature: "photos" },
  "/salute": { screen: "salute", feature: "health" },
  "/documenti": { screen: "documenti", feature: "documents" },
  "/spese": { screen: "spese", feature: "expenses" },
  "/wallet": { screen: "wallet", feature: "wallet" },
  "/password": { screen: "password", feature: "passwords" },
  "/posizione": { screen: "posizione", feature: "location" },
  "/animali": { screen: "animali", feature: "pets" },
  "/casa": { screen: "casa", feature: "home_vehicles" },
  "/garage": { screen: "garage", feature: "home_vehicles" },
  "/viaggi": { screen: "viaggi", feature: "travel" },
};

/**
 * Sezioni con un'AI propria, dove il pulsante dell'assistente di famiglia non
 * compare: due cerchi uguali nello stesso angolo, per due chat diverse, non si
 * distinguerebbero. Salute ha le sue chat (e Piano Alimentare e Fitness vivono
 * dentro Salute), Viaggi costruisce l'itinerario con l'AI, `/assistente` è la
 * chat stessa. Una sezione nuova con la sua AI va aggiunta qui.
 */
const OWN_AI_PREFIXES = ["/salute", "/viaggi", "/assistente"];

const hasOwnAI = (pathname) =>
  OWN_AI_PREFIXES.some((p) => pathname === p || pathname.startsWith(`${p}/`));

export default function Layout() {
  const location = useLocation();
  const { t } = useTranslation();
  /* La sezione in cui il pannello è stato aperto: cambiando sezione si chiude
     da solo, senza un effetto che lo rincorra. */
  const [assistantOpenOn, setAssistantOpenOn] = useState(null);
  const assistantOpen = assistantOpenOn === location.pathname;
  const closeAssistant = () => setAssistantOpenOn(null);
  /* Montato alla prima apertura e poi solo nascosto: chiudere il pannello
     mentre l'assistente sta rispondendo (o eseguendo azioni) non deve
     interrompere niente, e riaprirlo ritrova la chat dov'era. */
  const [assistantMounted, setAssistantMounted] = useState(false);
  const showAssistantFab = !hasOwnAI(location.pathname);

  const openAssistant = () => {
    setAssistantMounted(true);
    setAssistantOpenOn(location.pathname);
  };

  useEffect(() => {
    if (!assistantOpen) return undefined;
    const onKey = (e) => {
      if (e.key === "Escape") setAssistantOpenOn(null);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [assistantOpen]);

  // Una sola volta per caricamento della pagina, come `trackAppOpen` sui nativi.
  useEffect(() => {
    trackAppOpen();
  }, []);

  useEffect(() => {
    const entry = SCREENS[location.pathname];
    if (!entry) return;
    screenView(entry.screen);
    if (entry.feature) featureFirstUse(entry.feature);
  }, [location.pathname]);

  return (
    <div className="app-shell">
      <Sidebar />
      <main className="app-content">
        <Outlet />
      </main>

      {showAssistantFab && !assistantOpen && (
        <AIFab label={t.assistant.fabLabel} onClick={openAssistant} />
      )}

      {assistantMounted && (
        <div
          className="ai-panel-overlay"
          hidden={!assistantOpen}
          onClick={closeAssistant}
        >
          <div
            className="ai-panel-sheet"
            role="dialog"
            aria-label={t.assistant.fabLabel}
            onClick={(e) => e.stopPropagation()}
          >
            <Assistente variant="panel" onClose={closeAssistant} />
          </div>
        </div>
      )}
    </div>
  );
}
