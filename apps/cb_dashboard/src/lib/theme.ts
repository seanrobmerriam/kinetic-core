"use client";

import { useEffect, useState } from "react";

const THEME_STORAGE_KEY = "ironledger.theme";

export function useTheme(): { theme: "light" | "dark"; toggle: () => void } {
  const [theme, setTheme] = useState<"light" | "dark">("light");

  useEffect(() => {
    if (typeof document === "undefined") return;
    const attr = document.documentElement.getAttribute("data-theme");
    if (attr === "dark" || attr === "light") {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setTheme(attr);
    }
  }, []);

  const toggle = () => {
    if (typeof document === "undefined") return;
    const next: "light" | "dark" = theme === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", next);
    try {
      window.localStorage.setItem(THEME_STORAGE_KEY, next);
    } catch {
      /* ignore */
    }
    setTheme(next);
  };

  return { theme, toggle };
}
