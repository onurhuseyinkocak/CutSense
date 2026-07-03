"use client";

import {
  createContext,
  type ReactNode,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";

type SiteLanguage = "en" | "tr";

type LanguageContextValue = {
  language: SiteLanguage;
  setLanguage: (language: SiteLanguage) => void;
  t: (tr: string, en: string) => string;
};

const storageKey = "cutsense_language";

const LanguageContext = createContext<LanguageContextValue | null>(null);

function preferredLanguage(): SiteLanguage {
  if (typeof window === "undefined") {
    return "en";
  }

  const saved = window.localStorage.getItem(storageKey);
  if (saved === "tr" || saved === "en") {
    return saved;
  }

  return window.navigator.language.toLowerCase().startsWith("tr") ? "tr" : "en";
}

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [language, setLanguageState] = useState<SiteLanguage>("en");

  useEffect(() => {
    // Local storage is only available after hydration; keep SSR stable in English.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setLanguageState(preferredLanguage());
  }, []);

  useEffect(() => {
    document.documentElement.lang = language;
    window.localStorage.setItem(storageKey, language);
  }, [language]);

  const value = useMemo<LanguageContextValue>(
    () => ({
      language,
      setLanguage: setLanguageState,
      t: (tr, en) => (language === "tr" ? tr : en),
    }),
    [language],
  );

  return (
    <LanguageContext.Provider value={value}>
      {children}
    </LanguageContext.Provider>
  );
}

export function useLanguage() {
  const context = useContext(LanguageContext);
  if (!context) {
    throw new Error("useLanguage must be used inside LanguageProvider");
  }
  return context;
}

export function LanguageToggle() {
  const { language, setLanguage } = useLanguage();

  return (
    <div className="language-toggle" aria-label="Language">
      <button
        type="button"
        className={language === "tr" ? "active" : undefined}
        aria-pressed={language === "tr"}
        onClick={() => setLanguage("tr")}
      >
        TR
      </button>
      <button
        type="button"
        className={language === "en" ? "active" : undefined}
        aria-pressed={language === "en"}
        onClick={() => setLanguage("en")}
      >
        EN
      </button>
    </div>
  );
}
