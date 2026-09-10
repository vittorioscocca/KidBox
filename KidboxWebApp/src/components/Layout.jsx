import { useEffect } from "react";
import { Outlet, useLocation } from "react-router-dom";
import Sidebar from "./Sidebar";
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

export default function Layout() {
  const location = useLocation();

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
    </div>
  );
}
