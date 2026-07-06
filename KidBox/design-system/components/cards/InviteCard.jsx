import React from "react";

/**
 * KidBox InviteCard — the "Invita l'altro genitore" prompt (InviteCardView.swift).
 * Frosted surface, leading icon, title + subtitle, trailing chevron.
 */
export function InviteCard({
  title = "Invita l'altro genitore",
  subtitle = "Genera un codice e condividilo in 2 secondi.",
  icon = null,
  onClick,
  style = {},
  ...rest
}) {
  return (
    <button
      onClick={onClick}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 12,
        width: "100%",
        padding: "var(--kb-space-8)",
        textAlign: "left",
        cursor: "pointer",
        border: "1px solid var(--kb-border)",
        borderRadius: "var(--kb-radius-md)",
        background: "var(--kb-surface-2)",
        boxShadow: "var(--kb-shadow-ios)",
        fontFamily: "var(--kb-font-sans)",
        ...style,
      }}
      {...rest}
    >
      <span style={{ color: "var(--kb-orange)", display: "inline-flex", fontSize: 22 }}>
        {icon || (
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="9" cy="8" r="4" /><path d="M2 20c0-3.5 3-5.5 7-5.5" /><path d="M19 8v6M22 11h-6" />
          </svg>
        )}
      </span>
      <span style={{ display: "flex", flexDirection: "column", gap: 4, flex: 1, minWidth: 0 }}>
        <span style={{ fontSize: "var(--kb-text-headline)", fontWeight: "var(--kb-weight-bold)", color: "var(--kb-text)" }}>{title}</span>
        <span style={{ fontSize: "var(--kb-text-subheadline)", color: "var(--kb-text-secondary)", lineHeight: 1.3 }}>{subtitle}</span>
      </span>
      <span style={{ color: "var(--kb-text-secondary)", display: "inline-flex" }}>
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="m9 18 6-6-6-6" /></svg>
      </span>
    </button>
  );
}
