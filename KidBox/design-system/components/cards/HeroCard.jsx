import React from "react";

/**
 * KidBox HeroCard — the family photo hero at the top of Home (HomeHeroCard.swift).
 * Full-bleed image, dark bottom protection gradient, date + member badge on top,
 * title/subtitle and a frosted "change photo" affordance at the bottom.
 * Falls back to a warm placeholder when no photo is set.
 */
export function HeroCard({
  title = "La tua famiglia",
  subtitle = "",
  dateText = "",
  badgeText = "",
  photo = null,
  actionLabel = "Tocca per cambiare foto",
  height = 300,
  onClick,
  style = {},
  ...rest
}) {
  return (
    <button
      onClick={onClick}
      style={{
        position: "relative",
        display: "block",
        width: "100%",
        height,
        padding: 0,
        border: "none",
        borderRadius: "var(--kb-radius-hero)",
        overflow: "hidden",
        cursor: "pointer",
        background: photo
          ? `center/cover no-repeat url(${photo})`
          : "linear-gradient(135deg, var(--kb-orange), var(--kb-ai-orange-deep))",
        fontFamily: "var(--kb-font-sans)",
        textAlign: "left",
        ...style,
      }}
      {...rest}
    >
      {/* protection gradient */}
      <span style={{
        position: "absolute", inset: 0,
        background: "linear-gradient(to bottom, rgba(0,0,0,0.05) 0%, rgba(0,0,0,0.60) 100%)",
      }} />

      {/* top row: date + member badge */}
      <span style={{
        position: "absolute", top: 12, left: 14, right: 14,
        display: "flex", alignItems: "center", justifyContent: "space-between",
      }}>
        <span style={{ color: "rgba(255,255,255,0.85)", fontSize: "var(--kb-text-caption)" }}>{dateText}</span>
        {badgeText && (
          <span style={{
            color: "#fff", fontSize: "var(--kb-text-caption2)", fontWeight: "var(--kb-weight-bold)",
            padding: "6px 8px", background: "rgba(255,255,255,0.18)", borderRadius: "var(--kb-radius-pill)",
            backdropFilter: "blur(6px)",
          }}>{badgeText}</span>
        )}
      </span>

      {/* bottom block */}
      <span style={{ position: "absolute", left: 14, right: 14, bottom: 14, display: "flex", flexDirection: "column", gap: 8 }}>
        <span style={{ color: "#fff", fontSize: "var(--kb-text-title2)", fontWeight: "var(--kb-weight-heavy)", lineHeight: 1.1 }}>{title}</span>
        {subtitle && <span style={{ color: "rgba(255,255,255,0.9)", fontSize: "var(--kb-text-subheadline)" }}>{subtitle}</span>}
        <span style={{
          display: "inline-flex", alignSelf: "flex-start", alignItems: "center", gap: 8,
          marginTop: 2, padding: "10px 12px",
          color: "#fff", fontSize: "var(--kb-text-subheadline)", fontWeight: "var(--kb-weight-bold)",
          background: "rgba(255,255,255,0.18)", borderRadius: "var(--kb-radius-sm)", backdropFilter: "blur(6px)",
        }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <rect x="3" y="5" width="18" height="14" rx="2" /><circle cx="9" cy="11" r="2" /><path d="m21 17-4.5-4.5L9 20" />
          </svg>
          {actionLabel}
        </span>
      </span>
    </button>
  );
}
