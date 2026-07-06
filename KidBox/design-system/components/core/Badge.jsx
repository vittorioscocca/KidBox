import React from "react";

/**
 * KidBox Badge — the small red count marker overlaid on Home cards
 * (BadgeView in HomeView.swift). Circle under 10, capsule at 10+.
 */
export function Badge({ count = 0, max = 99, tone = "danger", style = {} }) {
  if (!count || count <= 0) return null;
  const text = count > max ? `${max}+` : `${count}`;
  const isCircle = count < 10;
  const tones = {
    danger: "var(--kb-danger)",
    orange: "var(--kb-orange)",
    green: "var(--kb-success)",
    blue: "var(--kb-info)",
  };
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        minWidth: 18,
        height: 18,
        padding: isCircle ? 0 : "0 7px",
        width: isCircle ? 18 : "auto",
        background: tones[tone] || tones.danger,
        color: "#fff",
        fontFamily: "var(--kb-font-sans)",
        fontSize: "var(--kb-text-caption2)",
        fontWeight: "var(--kb-weight-bold)",
        lineHeight: 1,
        borderRadius: "var(--kb-radius-pill)",
        boxShadow: "0 1px 3px rgba(0,0,0,0.15)",
        ...style,
      }}
    >
      {text}
    </span>
  );
}
