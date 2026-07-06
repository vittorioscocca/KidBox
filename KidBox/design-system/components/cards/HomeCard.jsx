import React from "react";
import { Badge } from "../core/Badge.jsx";

/**
 * KidBox HomeCard — the tinted category tile from the Home grid
 * (HomeCardView / HomeCardLabel in HomeView.swift). Fills its tint at 10%,
 * borders it at 18%, radius 16, min-height 120. Optional red count badge.
 */
export function HomeCard({
  title,
  subtitle,
  icon = null,
  tint = "var(--kb-cat-orange)",
  badge = 0,
  locked = false,
  onClick,
  style = {},
  ...rest
}) {
  const [pressed, setPressed] = React.useState(false);
  return (
    <button
      onClick={onClick}
      onPointerDown={() => setPressed(true)}
      onPointerUp={() => setPressed(false)}
      onPointerLeave={() => setPressed(false)}
      style={{
        position: "relative",
        display: "flex",
        flexDirection: "column",
        alignItems: "flex-start",
        gap: "10px",
        width: "100%",
        minHeight: 120,
        padding: "var(--kb-space-7)",
        textAlign: "left",
        cursor: "pointer",
        border: `1px solid color-mix(in srgb, ${tint} 18%, transparent)`,
        borderRadius: "var(--kb-radius-md)",
        background: `color-mix(in srgb, ${tint} 10%, var(--kb-surface))`,
        transform: pressed ? "scale(0.98)" : "scale(1)",
        transition: "transform .15s ease",
        fontFamily: "var(--kb-font-sans)",
        ...style,
      }}
      {...rest}
    >
      <span style={{ display: "flex", width: "100%", alignItems: "center" }}>
        <span style={{ color: tint, display: "inline-flex", fontSize: 22 }}>{icon}</span>
        <span style={{ flex: 1 }} />
        {locked && (
          <span style={{ color: "var(--kb-text-secondary)", display: "inline-flex" }}>
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <rect x="5" y="11" width="14" height="10" rx="2" /><path d="M8 11V7a4 4 0 0 1 8 0v4" />
            </svg>
          </span>
        )}
      </span>
      <span style={{ display: "flex", flexDirection: "column", gap: 2 }}>
        <span style={{ fontSize: "var(--kb-text-headline)", fontWeight: "var(--kb-weight-bold)", color: "var(--kb-text)" }}>
          {title}
        </span>
        {subtitle && (
          <span style={{ fontSize: "var(--kb-text-subheadline)", color: "var(--kb-text-secondary)", lineHeight: 1.3 }}>
            {subtitle}
          </span>
        )}
      </span>
      {badge > 0 && (
        <span style={{ position: "absolute", top: 8, right: 8 }}>
          <Badge count={badge} />
        </span>
      )}
    </button>
  );
}
