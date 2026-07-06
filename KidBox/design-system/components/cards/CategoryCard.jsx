import React from "react";
import { Chip } from "../core/Chip.jsx";

/**
 * KidBox CategoryCard — the folder tile used in Documents (CategoryCard.swift).
 * Neutral surface, folder icon, title, "Apri categoria" hint, and an optional
 * sync-state pill top-right.
 */
export function CategoryCard({
  title,
  hint = "Apri categoria",
  icon = null,
  syncLabel = null,
  syncTone = "green",
  onClick,
  style = {},
  ...rest
}) {
  const syncColors = { green: "var(--kb-cat-green)", orange: "var(--kb-warning)", red: "var(--kb-danger)" };
  return (
    <button
      onClick={onClick}
      style={{
        display: "flex",
        flexDirection: "column",
        gap: 10,
        width: "100%",
        minHeight: 92,
        padding: "var(--kb-space-7)",
        textAlign: "left",
        cursor: "pointer",
        background: "var(--kb-surface)",
        border: "1px solid var(--kb-border)",
        borderRadius: "var(--kb-radius-md)",
        boxShadow: "var(--kb-shadow-ios)",
        fontFamily: "var(--kb-font-sans)",
        ...style,
      }}
      {...rest}
    >
      <span style={{ display: "flex", alignItems: "center", width: "100%" }}>
        <span style={{ color: "var(--kb-text-secondary)", display: "inline-flex" }}>
          {icon || (
            <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
              <path d="M10 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-8l-2-2z" />
            </svg>
          )}
        </span>
        <span style={{ flex: 1 }} />
        {syncLabel && (
          <Chip tint={syncColors[syncTone]} variant="tinted">{syncLabel}</Chip>
        )}
      </span>
      <span style={{ fontSize: "var(--kb-text-headline)", fontWeight: "var(--kb-weight-bold)", color: "var(--kb-text)" }}>{title}</span>
      <span style={{ fontSize: "var(--kb-text-caption)", color: "var(--kb-text-secondary)" }}>{hint}</span>
    </button>
  );
}
