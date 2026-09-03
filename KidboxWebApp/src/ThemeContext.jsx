/**
 * Tema dell'interfaccia: Chiaro / Scuro / Sistema, come `AppearanceSettingsView`
 * su iOS.
 *
 * È una preferenza del browser, non dell'account: iOS la tiene in
 * `UserDefaults` e non la sincronizza, quindi nemmeno qui finisce su Firestore.
 * La scelta viene scritta su `<html data-theme>`, che è ciò che le variabili
 * CSS in `index.css` osservano; `system` toglie l'attributo e lascia decidere a
 * `prefers-color-scheme`.
 */
import { createContext, useContext, useEffect, useMemo, useState } from "react";

const STORAGE_KEY = "kidbox:theme";

export const THEMES = [
  { value: "light", icon: "☀️" },
  { value: "dark", icon: "🌙" },
  { value: "system", icon: "◐" },
];

const ThemeContext = createContext(null);

function readStored() {
  const stored = localStorage.getItem(STORAGE_KEY);
  return THEMES.some((t) => t.value === stored) ? stored : "system";
}

export function applyTheme(theme) {
  const root = document.documentElement;
  if (theme === "system") root.removeAttribute("data-theme");
  else root.setAttribute("data-theme", theme);
}

export function ThemeProvider({ children }) {
  const [theme, setThemeState] = useState(readStored);

  useEffect(() => {
    applyTheme(theme);
  }, [theme]);

  const value = useMemo(
    () => ({
      theme,
      setTheme: (next) => {
        localStorage.setItem(STORAGE_KEY, next);
        setThemeState(next);
      },
    }),
    [theme]
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error("useTheme must be used within ThemeProvider");
  return ctx;
}
