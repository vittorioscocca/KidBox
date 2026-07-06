import React from "react";

/**
 * KidBox AskAIButton — the circular "parla con l'AI" FAB (AIActionButton.swift).
 * Orange gradient, sparkles glyph, white inner ring, soft glow and a gentle
 * breathing pulse. Size `fab` (58px, floating) or `sm` inline.
 */
export function AskAIButton({
  size = "fab",
  label = "Chiedi all'AI",
  pulse = true,
  onClick,
  style = {},
  ...rest
}) {
  const d = size === "sm" ? 42 : 58;
  const glyph = size === "sm" ? 16 : 22;
  return (
    <>
      <style>{`@keyframes kbAiPulse{0%,100%{transform:scale(0.98)}50%{transform:scale(1.02)}}`}</style>
      <button
        onClick={onClick}
        aria-label={label}
        style={{
          position: "relative",
          width: d,
          height: d,
          display: "inline-flex",
          alignItems: "center",
          justifyContent: "center",
          border: "1.5px solid rgba(255,255,255,0.22)",
          borderRadius: "50%",
          cursor: "pointer",
          color: "#fff",
          background: "linear-gradient(135deg, var(--kb-ai-orange), var(--kb-ai-orange-deep))",
          boxShadow: "var(--kb-shadow-ai)",
          animation: pulse ? "kbAiPulse 1.6s ease-in-out infinite" : "none",
          ...style,
        }}
        {...rest}
      >
        <svg width={glyph} height={glyph} viewBox="0 0 24 24" fill="currentColor">
          <path d="M12 3l1.6 4.3L18 9l-4.4 1.7L12 15l-1.6-4.3L6 9l4.4-1.7L12 3z" />
          <path d="M19 14l.8 2.2L22 17l-2.2.8L19 20l-.8-2.2L16 17l2.2-.8L19 14z" />
        </svg>
      </button>
    </>
  );
}
