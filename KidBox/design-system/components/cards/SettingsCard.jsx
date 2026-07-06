import React from "react";

/**
 * KidBox SettingsCard — the list row card from Settings (KBSettingsCard.swift).
 * Leading icon tinted by `tone`, title + subtitle, optional trailing action.
 * Neutral surface fill with a hairline border matching the tone.
 */
export function SettingsCard({
  title,
  subtitle,
  icon = null,
  tone = "primary",
  trailing = null,
  onClick,
  children,
  style = {},
  ...rest
}) {
  const tones = {
    primary:   { icon: "var(--kb-orange)",  border: "var(--kb-border-strong)" },
    secondary: { icon: "var(--kb-text-secondary)", border: "var(--kb-border)" },
    info:      { icon: "var(--kb-info)",    border: "color-mix(in srgb, var(--kb-info) 20%, transparent)" },
    warning:   { icon: "var(--kb-warning)", border: "color-mix(in srgb, var(--kb-warning) 25%, transparent)" },
    danger:    { icon: "var(--kb-danger)",  border: "color-mix(in srgb, var(--kb-danger) 25%, transparent)" },
  };
  const t = tones[tone] || tones.primary;
  const Wrapper = onClick ? "button" : "div";
  return (
    <Wrapper
      onClick={onClick}
      style={{
        display: "flex",
        flexDirection: "column",
        gap: children ? 10 : 0,
        width: "100%",
        padding: "var(--kb-space-7)",
        textAlign: "left",
        cursor: onClick ? "pointer" : "default",
        background: "var(--kb-surface)",
        border: `1px solid ${t.border}`,
        borderRadius: "var(--kb-radius-md)",
        boxShadow: "var(--kb-shadow-ios)",
        fontFamily: "var(--kb-font-sans)",
        ...style,
      }}
      {...rest}
    >
      <span style={{ display: "flex", alignItems: "flex-start", gap: 12, width: "100%" }}>
        {icon && <span style={{ color: t.icon, display: "inline-flex", fontSize: 20, marginTop: 1 }}>{icon}</span>}
        <span style={{ display: "flex", flexDirection: "column", gap: 4, flex: 1, minWidth: 0 }}>
          <span style={{ fontSize: "var(--kb-text-headline)", fontWeight: "var(--kb-weight-bold)", color: "var(--kb-text)" }}>
            {title}
          </span>
          {subtitle && (
            <span style={{ fontSize: "var(--kb-text-subheadline)", color: "var(--kb-text-secondary)", lineHeight: 1.35 }}>
              {subtitle}
            </span>
          )}
        </span>
        {trailing && <span style={{ display: "inline-flex", alignItems: "center" }}>{trailing}</span>}
      </span>
      {children}
    </Wrapper>
  );
}
