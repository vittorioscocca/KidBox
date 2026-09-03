import { createContext, useContext, useEffect, useMemo, useState } from "react";
import { translations } from "./translations";

const LocaleContext = createContext(null);

const STORAGE_KEY = "kidbox:locale";

function detectLocale() {
  const stored = localStorage.getItem(STORAGE_KEY);
  if (stored && translations[stored]) return stored;
  const nav = (navigator.language || "it").slice(0, 2);
  return translations[nav] ? nav : "it";
}

export function LocaleProvider({ children }) {
  const [locale, setLocaleState] = useState(detectLocale);

  // `lang` sul documento: senza, il browser continua a trattare la pagina come
  // italiana per sillabazione, correttore e lettori di schermo.
  useEffect(() => {
    document.documentElement.lang = locale;
  }, [locale]);

  const value = useMemo(
    () => ({
      locale,
      t: translations[locale],
      setLocale: (next) => {
        if (!translations[next]) return;
        localStorage.setItem(STORAGE_KEY, next);
        setLocaleState(next);
      },
    }),
    [locale]
  );

  return <LocaleContext.Provider value={value}>{children}</LocaleContext.Provider>;
}

export function useTranslation() {
  const ctx = useContext(LocaleContext);
  if (!ctx) throw new Error("useTranslation must be used within LocaleProvider");
  return ctx;
}
