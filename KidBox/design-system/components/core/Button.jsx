import React from "react";

/**
 * KidBox Button — mirrors the LoginView "ink" primary button plus the
 * marketing secondary/ghost pills and the AI-orange gradient call-to-action.
 */
export function Button({
  children,
  variant = "primary",
  size = "md",
  icon = null,
  iconRight = null,
  fullWidth = false,
  disabled = false,
  onClick,
  type = "button",
  style = {},
  ...rest
}) {
  const sizes = {
    sm: { padding: "8px 16px", font: "var(--kb-text-footnote)", gap: "6px", radius: "var(--kb-radius-pill)" },
    md: { padding: "12px 22px", font: "var(--kb-text-subheadline)", gap: "8px", radius: "var(--kb-radius-pill)" },
    lg: { padding: "15px 28px", font: "var(--kb-text-headline)", gap: "10px", radius: "var(--kb-radius-pill)" },
  };
  const s = sizes[size] || sizes.md;

  const base = {
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    gap: s.gap,
    width: fullWidth ? "100%" : "auto",
    padding: s.padding,
    fontFamily: "var(--kb-font-sans)",
    fontSize: s.font,
    fontWeight: "var(--kb-weight-bold)",
    lineHeight: 1,
    letterSpacing: "-0.01em",
    borderRadius: s.radius,
    border: "1.5px solid transparent",
    cursor: disabled ? "not-allowed" : "pointer",
    opacity: disabled ? 0.45 : 1,
    transition: "transform .15s ease, opacity .2s ease, background .2s ease, border-color .2s ease",
    WebkitTapHighlightColor: "transparent",
    userSelect: "none",
  };

  const variants = {
    primary: {
      background: "var(--kb-btn-primary-bg)",
      color: "var(--kb-btn-primary-fg)",
    },
    accent: {
      background: "var(--kb-orange)",
      color: "var(--kb-on-accent)",
      boxShadow: "0 4px 14px rgba(232,131,58,0.3)",
    },
    ai: {
      background: "linear-gradient(135deg, var(--kb-ai-orange), var(--kb-ai-orange-deep))",
      color: "#fff",
      boxShadow: "var(--kb-shadow-ai)",
      border: "1.5px solid rgba(255,255,255,0.22)",
    },
    secondary: {
      background: "transparent",
      color: "var(--kb-text)",
      borderColor: "var(--kb-border-strong)",
    },
    ghost: {
      background: "transparent",
      color: "var(--kb-orange-deep)",
    },
    danger: {
      background: "var(--kb-danger)",
      color: "#fff",
    },
  };

  return (
    <button
      type={type}
      disabled={disabled}
      onClick={onClick}
      style={{ ...base, ...(variants[variant] || variants.primary), ...style }}
      onMouseDown={(e) => { if (!disabled) e.currentTarget.style.transform = "scale(0.97)"; }}
      onMouseUp={(e) => { e.currentTarget.style.transform = "scale(1)"; }}
      onMouseLeave={(e) => { e.currentTarget.style.transform = "scale(1)"; }}
      {...rest}
    >
      {icon}
      {children}
      {iconRight}
    </button>
  );
}
