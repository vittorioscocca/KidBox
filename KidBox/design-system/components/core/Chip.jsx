import React from "react";

/**
 * KidBox Chip — the rounded pill used for visibility tags ("Tutta la famiglia"),
 * marketing feature tags and filter pills. Neutral by default; pass a `tint`
 * category color for a soft tinted variant.
 */
export function Chip({
  children,
  tint = null,
  variant = "neutral",
  icon = null,
  style = {},
  ...rest
}) {
  const isTinted = variant === "tinted" && tint;
  const base = {
    display: "inline-flex",
    alignItems: "center",
    gap: "6px",
    padding: "5px 12px",
    fontFamily: "var(--kb-font-sans)",
    fontSize: "var(--kb-text-caption)",
    fontWeight: "var(--kb-weight-semibold)",
    lineHeight: 1.2,
    borderRadius: "var(--kb-radius-pill)",
    whiteSpace: "nowrap",
  };
  const styles = isTinted
    ? {
        background: `color-mix(in srgb, ${tint} 14%, transparent)`,
        color: tint,
        border: `1px solid color-mix(in srgb, ${tint} 26%, transparent)`,
      }
    : {
        background: "var(--kb-chip-bg)",
        color: "var(--kb-chip-fg)",
        border: "1px solid var(--kb-border)",
      };
  return (
    <span style={{ ...base, ...styles, ...style }} {...rest}>
      {icon}
      {children}
    </span>
  );
}
