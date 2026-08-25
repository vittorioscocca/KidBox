import { createContext, useContext, useMemo } from "react";
import { translations } from "./translations";

const LocaleContext = createContext(null);

function detectLocale() {
  const stored = localStorage.getItem("kidbox:locale");
  if (stored && translations[stored]) return stored;
  const nav = (navigator.language || "it").slice(0, 2);
  return translations[nav] ? nav : "it";
}

export function LocaleProvider({ children }) {
  const locale = useMemo(detectLocale, []);
  const value = useMemo(() => ({ locale, t: translations[locale] }), [locale]);
  return <LocaleContext.Provider value={value}>{children}</LocaleContext.Provider>;
}

export function useTranslation() {
  const ctx = useContext(LocaleContext);
  if (!ctx) throw new Error("useTranslation must be used within LocaleProvider");
  return ctx;
}
