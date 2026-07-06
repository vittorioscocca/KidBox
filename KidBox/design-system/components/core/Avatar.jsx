import React from "react";

/**
 * KidBox Avatar — circular profile image with a hairline ring (ProfileAvatarView
 * in HomeView.swift). Falls back to initials, then a neutral person tint.
 */
export function Avatar({ src = null, name = "", size = 40, style = {}, ...rest }) {
  const initials = name
    ? name.trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join("").toUpperCase()
    : "";
  const ring = {
    width: size,
    height: size,
    borderRadius: "50%",
    overflow: "hidden",
    flexShrink: 0,
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    background: src ? "transparent" : "var(--kb-orange-soft)",
    color: "var(--kb-orange-deep)",
    fontFamily: "var(--kb-font-sans)",
    fontWeight: "var(--kb-weight-bold)",
    fontSize: Math.max(11, Math.round(size * 0.4)),
    boxShadow: "inset 0 0 0 1px var(--kb-border)",
    ...style,
  };
  return (
    <span style={ring} {...rest}>
      {src ? (
        <img src={src} alt={name} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
      ) : initials ? (
        initials
      ) : (
        <svg width={size * 0.6} height={size * 0.6} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="8" r="4" />
          <path d="M4 20c0-4 3.6-6 8-6s8 2 8 6" />
        </svg>
      )}
    </span>
  );
}
