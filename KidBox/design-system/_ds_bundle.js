/* @ds-bundle: {"format":4,"namespace":"KidBoxDesignSystem_d1a58b","components":[{"name":"AskAIButton","sourcePath":"components/ai/AskAIButton.jsx"},{"name":"CategoryCard","sourcePath":"components/cards/CategoryCard.jsx"},{"name":"HeroCard","sourcePath":"components/cards/HeroCard.jsx"},{"name":"HomeCard","sourcePath":"components/cards/HomeCard.jsx"},{"name":"InviteCard","sourcePath":"components/cards/InviteCard.jsx"},{"name":"SettingsCard","sourcePath":"components/cards/SettingsCard.jsx"},{"name":"Avatar","sourcePath":"components/core/Avatar.jsx"},{"name":"Badge","sourcePath":"components/core/Badge.jsx"},{"name":"Button","sourcePath":"components/core/Button.jsx"},{"name":"Chip","sourcePath":"components/core/Chip.jsx"}],"sourceHashes":{"components/ai/AskAIButton.jsx":"71005355fb93","components/cards/CategoryCard.jsx":"7f75ff957624","components/cards/HeroCard.jsx":"24ac40ae78a4","components/cards/HomeCard.jsx":"a914645fc5aa","components/cards/InviteCard.jsx":"dfe73567ee10","components/cards/SettingsCard.jsx":"edd03446dd77","components/core/Avatar.jsx":"71d3d7c5e1d4","components/core/Badge.jsx":"b75eccc12334","components/core/Button.jsx":"e398e030649b","components/core/Chip.jsx":"c1a23a3ecae3","ui_kits/mobile-app/DocumentsScreen.jsx":"c7700a7e526d","ui_kits/mobile-app/HomeScreen.jsx":"46e0cf52f359","ui_kits/mobile-app/Icons.jsx":"ad1865b36d11","ui_kits/mobile-app/LoginScreen.jsx":"313979a36880","ui_kits/mobile-app/SettingsScreen.jsx":"e7c04a865642","ui_kits/mobile-app/ios-frame.jsx":"be3343be4b51"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.KidBoxDesignSystem_d1a58b = window.KidBoxDesignSystem_d1a58b || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/ai/AskAIButton.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * KidBox AskAIButton — the circular "parla con l'AI" FAB (AIActionButton.swift).
 * Orange gradient, sparkles glyph, white inner ring, soft glow and a gentle
 * breathing pulse. Size `fab` (58px, floating) or `sm` inline.
 */
function AskAIButton({
  size = "fab",
  label = "Chiedi all'AI",
  pulse = true,
  onClick,
  style = {},
  ...rest
}) {
  const d = size === "sm" ? 42 : 58;
  const glyph = size === "sm" ? 16 : 22;
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("style", null, `@keyframes kbAiPulse{0%,100%{transform:scale(0.98)}50%{transform:scale(1.02)}}`), /*#__PURE__*/React.createElement("button", _extends({
    onClick: onClick,
    "aria-label": label,
    style: {
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
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("svg", {
    width: glyph,
    height: glyph,
    viewBox: "0 0 24 24",
    fill: "currentColor"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M12 3l1.6 4.3L18 9l-4.4 1.7L12 15l-1.6-4.3L6 9l4.4-1.7L12 3z"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M19 14l.8 2.2L22 17l-2.2.8L19 20l-.8-2.2L16 17l2.2-.8L19 14z"
  }))));
}
Object.assign(__ds_scope, { AskAIButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/ai/AskAIButton.jsx", error: String((e && e.message) || e) }); }

// components/cards/HeroCard.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * KidBox HeroCard — the family photo hero at the top of Home (HomeHeroCard.swift).
 * Full-bleed image, dark bottom protection gradient, date + member badge on top,
 * title/subtitle and a frosted "change photo" affordance at the bottom.
 * Falls back to a warm placeholder when no photo is set.
 */
function HeroCard({
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
  return /*#__PURE__*/React.createElement("button", _extends({
    onClick: onClick,
    style: {
      position: "relative",
      display: "block",
      width: "100%",
      height,
      padding: 0,
      border: "none",
      borderRadius: "var(--kb-radius-hero)",
      overflow: "hidden",
      cursor: "pointer",
      background: photo ? `center/cover no-repeat url(${photo})` : "linear-gradient(135deg, var(--kb-orange), var(--kb-ai-orange-deep))",
      fontFamily: "var(--kb-font-sans)",
      textAlign: "left",
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      inset: 0,
      background: "linear-gradient(to bottom, rgba(0,0,0,0.05) 0%, rgba(0,0,0,0.60) 100%)"
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      top: 12,
      left: 14,
      right: 14,
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: "rgba(255,255,255,0.85)",
      fontSize: "var(--kb-text-caption)"
    }
  }, dateText), badgeText && /*#__PURE__*/React.createElement("span", {
    style: {
      color: "#fff",
      fontSize: "var(--kb-text-caption2)",
      fontWeight: "var(--kb-weight-bold)",
      padding: "6px 8px",
      background: "rgba(255,255,255,0.18)",
      borderRadius: "var(--kb-radius-pill)",
      backdropFilter: "blur(6px)"
    }
  }, badgeText)), /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      left: 14,
      right: 14,
      bottom: 14,
      display: "flex",
      flexDirection: "column",
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: "#fff",
      fontSize: "var(--kb-text-title2)",
      fontWeight: "var(--kb-weight-heavy)",
      lineHeight: 1.1
    }
  }, title), subtitle && /*#__PURE__*/React.createElement("span", {
    style: {
      color: "rgba(255,255,255,0.9)",
      fontSize: "var(--kb-text-subheadline)"
    }
  }, subtitle), /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      alignSelf: "flex-start",
      alignItems: "center",
      gap: 8,
      marginTop: 2,
      padding: "10px 12px",
      color: "#fff",
      fontSize: "var(--kb-text-subheadline)",
      fontWeight: "var(--kb-weight-bold)",
      background: "rgba(255,255,255,0.18)",
      borderRadius: "var(--kb-radius-sm)",
      backdropFilter: "blur(6px)"
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: "16",
    height: "16",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "1.8",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }, /*#__PURE__*/React.createElement("rect", {
    x: "3",
    y: "5",
    width: "18",
    height: "14",
    rx: "2"
  }), /*#__PURE__*/React.createElement("circle", {
    cx: "9",
    cy: "11",
    r: "2"
  }), /*#__PURE__*/React.createElement("path", {
    d: "m21 17-4.5-4.5L9 20"
  })), actionLabel)));
}
Object.assign(__ds_scope, { HeroCard });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/cards/HeroCard.jsx", error: String((e && e.message) || e) }); }

// components/cards/InviteCard.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * KidBox InviteCard — the "Invita l'altro genitore" prompt (InviteCardView.swift).
 * Frosted surface, leading icon, title + subtitle, trailing chevron.
 */
function InviteCard({
  title = "Invita l'altro genitore",
  subtitle = "Genera un codice e condividilo in 2 secondi.",
  icon = null,
  onClick,
  style = {},
  ...rest
}) {
  return /*#__PURE__*/React.createElement("button", _extends({
    onClick: onClick,
    style: {
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
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--kb-orange)",
      display: "inline-flex",
      fontSize: 22
    }
  }, icon || /*#__PURE__*/React.createElement("svg", {
    width: "24",
    height: "24",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "1.8",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }, /*#__PURE__*/React.createElement("circle", {
    cx: "9",
    cy: "8",
    r: "4"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M2 20c0-3.5 3-5.5 7-5.5"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M19 8v6M22 11h-6"
  }))), /*#__PURE__*/React.createElement("span", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 4,
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--kb-text-headline)",
      fontWeight: "var(--kb-weight-bold)",
      color: "var(--kb-text)"
    }
  }, title), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--kb-text-subheadline)",
      color: "var(--kb-text-secondary)",
      lineHeight: 1.3
    }
  }, subtitle)), /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--kb-text-secondary)",
      display: "inline-flex"
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: "18",
    height: "18",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "2.2",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }, /*#__PURE__*/React.createElement("path", {
    d: "m9 18 6-6-6-6"
  }))));
}
Object.assign(__ds_scope, { InviteCard });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/cards/InviteCard.jsx", error: String((e && e.message) || e) }); }

// components/cards/SettingsCard.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * KidBox SettingsCard — the list row card from Settings (KBSettingsCard.swift).
 * Leading icon tinted by `tone`, title + subtitle, optional trailing action.
 * Neutral surface fill with a hairline border matching the tone.
 */
function SettingsCard({
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
    primary: {
      icon: "var(--kb-orange)",
      border: "var(--kb-border-strong)"
    },
    secondary: {
      icon: "var(--kb-text-secondary)",
      border: "var(--kb-border)"
    },
    info: {
      icon: "var(--kb-info)",
      border: "color-mix(in srgb, var(--kb-info) 20%, transparent)"
    },
    warning: {
      icon: "var(--kb-warning)",
      border: "color-mix(in srgb, var(--kb-warning) 25%, transparent)"
    },
    danger: {
      icon: "var(--kb-danger)",
      border: "color-mix(in srgb, var(--kb-danger) 25%, transparent)"
    }
  };
  const t = tones[tone] || tones.primary;
  const Wrapper = onClick ? "button" : "div";
  return /*#__PURE__*/React.createElement(Wrapper, _extends({
    onClick: onClick,
    style: {
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
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("span", {
    style: {
      display: "flex",
      alignItems: "flex-start",
      gap: 12,
      width: "100%"
    }
  }, icon && /*#__PURE__*/React.createElement("span", {
    style: {
      color: t.icon,
      display: "inline-flex",
      fontSize: 20,
      marginTop: 1
    }
  }, icon), /*#__PURE__*/React.createElement("span", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 4,
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--kb-text-headline)",
      fontWeight: "var(--kb-weight-bold)",
      color: "var(--kb-text)"
    }
  }, title), subtitle && /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--kb-text-subheadline)",
      color: "var(--kb-text-secondary)",
      lineHeight: 1.35
    }
  }, subtitle)), trailing && /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      alignItems: "center"
    }
  }, trailing)), children);
}
Object.assign(__ds_scope, { SettingsCard });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/cards/SettingsCard.jsx", error: String((e && e.message) || e) }); }

// components/core/Avatar.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * KidBox Avatar — circular profile image with a hairline ring (ProfileAvatarView
 * in HomeView.swift). Falls back to initials, then a neutral person tint.
 */
function Avatar({
  src = null,
  name = "",
  size = 40,
  style = {},
  ...rest
}) {
  const initials = name ? name.trim().split(/\s+/).slice(0, 2).map(w => w[0]).join("").toUpperCase() : "";
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
    ...style
  };
  return /*#__PURE__*/React.createElement("span", _extends({
    style: ring
  }, rest), src ? /*#__PURE__*/React.createElement("img", {
    src: src,
    alt: name,
    style: {
      width: "100%",
      height: "100%",
      objectFit: "cover"
    }
  }) : initials ? initials : /*#__PURE__*/React.createElement("svg", {
    width: size * 0.6,
    height: size * 0.6,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "1.8",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }, /*#__PURE__*/React.createElement("circle", {
    cx: "12",
    cy: "8",
    r: "4"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M4 20c0-4 3.6-6 8-6s8 2 8 6"
  })));
}
Object.assign(__ds_scope, { Avatar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Avatar.jsx", error: String((e && e.message) || e) }); }

// components/core/Badge.jsx
try { (() => {
/**
 * KidBox Badge — the small red count marker overlaid on Home cards
 * (BadgeView in HomeView.swift). Circle under 10, capsule at 10+.
 */
function Badge({
  count = 0,
  max = 99,
  tone = "danger",
  style = {}
}) {
  if (!count || count <= 0) return null;
  const text = count > max ? `${max}+` : `${count}`;
  const isCircle = count < 10;
  const tones = {
    danger: "var(--kb-danger)",
    orange: "var(--kb-orange)",
    green: "var(--kb-success)",
    blue: "var(--kb-info)"
  };
  return /*#__PURE__*/React.createElement("span", {
    style: {
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
      ...style
    }
  }, text);
}
Object.assign(__ds_scope, { Badge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Badge.jsx", error: String((e && e.message) || e) }); }

// components/cards/HomeCard.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * KidBox HomeCard — the tinted category tile from the Home grid
 * (HomeCardView / HomeCardLabel in HomeView.swift). Fills its tint at 10%,
 * borders it at 18%, radius 16, min-height 120. Optional red count badge.
 */
function HomeCard({
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
  return /*#__PURE__*/React.createElement("button", _extends({
    onClick: onClick,
    onPointerDown: () => setPressed(true),
    onPointerUp: () => setPressed(false),
    onPointerLeave: () => setPressed(false),
    style: {
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
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("span", {
    style: {
      display: "flex",
      width: "100%",
      alignItems: "center"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: tint,
      display: "inline-flex",
      fontSize: 22
    }
  }, icon), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), locked && /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--kb-text-secondary)",
      display: "inline-flex"
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: "15",
    height: "15",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "2",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }, /*#__PURE__*/React.createElement("rect", {
    x: "5",
    y: "11",
    width: "14",
    height: "10",
    rx: "2"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M8 11V7a4 4 0 0 1 8 0v4"
  })))), /*#__PURE__*/React.createElement("span", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--kb-text-headline)",
      fontWeight: "var(--kb-weight-bold)",
      color: "var(--kb-text)"
    }
  }, title), subtitle && /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--kb-text-subheadline)",
      color: "var(--kb-text-secondary)",
      lineHeight: 1.3
    }
  }, subtitle)), badge > 0 && /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      top: 8,
      right: 8
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Badge, {
    count: badge
  })));
}
Object.assign(__ds_scope, { HomeCard });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/cards/HomeCard.jsx", error: String((e && e.message) || e) }); }

// components/core/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * KidBox Button — mirrors the LoginView "ink" primary button plus the
 * marketing secondary/ghost pills and the AI-orange gradient call-to-action.
 */
function Button({
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
    sm: {
      padding: "8px 16px",
      font: "var(--kb-text-footnote)",
      gap: "6px",
      radius: "var(--kb-radius-pill)"
    },
    md: {
      padding: "12px 22px",
      font: "var(--kb-text-subheadline)",
      gap: "8px",
      radius: "var(--kb-radius-pill)"
    },
    lg: {
      padding: "15px 28px",
      font: "var(--kb-text-headline)",
      gap: "10px",
      radius: "var(--kb-radius-pill)"
    }
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
    userSelect: "none"
  };
  const variants = {
    primary: {
      background: "var(--kb-btn-primary-bg)",
      color: "var(--kb-btn-primary-fg)"
    },
    accent: {
      background: "var(--kb-orange)",
      color: "var(--kb-on-accent)",
      boxShadow: "0 4px 14px rgba(232,131,58,0.3)"
    },
    ai: {
      background: "linear-gradient(135deg, var(--kb-ai-orange), var(--kb-ai-orange-deep))",
      color: "#fff",
      boxShadow: "var(--kb-shadow-ai)",
      border: "1.5px solid rgba(255,255,255,0.22)"
    },
    secondary: {
      background: "transparent",
      color: "var(--kb-text)",
      borderColor: "var(--kb-border-strong)"
    },
    ghost: {
      background: "transparent",
      color: "var(--kb-orange-deep)"
    },
    danger: {
      background: "var(--kb-danger)",
      color: "#fff"
    }
  };
  return /*#__PURE__*/React.createElement("button", _extends({
    type: type,
    disabled: disabled,
    onClick: onClick,
    style: {
      ...base,
      ...(variants[variant] || variants.primary),
      ...style
    },
    onMouseDown: e => {
      if (!disabled) e.currentTarget.style.transform = "scale(0.97)";
    },
    onMouseUp: e => {
      e.currentTarget.style.transform = "scale(1)";
    },
    onMouseLeave: e => {
      e.currentTarget.style.transform = "scale(1)";
    }
  }, rest), icon, children, iconRight);
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Button.jsx", error: String((e && e.message) || e) }); }

// components/core/Chip.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * KidBox Chip — the rounded pill used for visibility tags ("Tutta la famiglia"),
 * marketing feature tags and filter pills. Neutral by default; pass a `tint`
 * category color for a soft tinted variant.
 */
function Chip({
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
    whiteSpace: "nowrap"
  };
  const styles = isTinted ? {
    background: `color-mix(in srgb, ${tint} 14%, transparent)`,
    color: tint,
    border: `1px solid color-mix(in srgb, ${tint} 26%, transparent)`
  } : {
    background: "var(--kb-chip-bg)",
    color: "var(--kb-chip-fg)",
    border: "1px solid var(--kb-border)"
  };
  return /*#__PURE__*/React.createElement("span", _extends({
    style: {
      ...base,
      ...styles,
      ...style
    }
  }, rest), icon, children);
}
Object.assign(__ds_scope, { Chip });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Chip.jsx", error: String((e && e.message) || e) }); }

// components/cards/CategoryCard.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * KidBox CategoryCard — the folder tile used in Documents (CategoryCard.swift).
 * Neutral surface, folder icon, title, "Apri categoria" hint, and an optional
 * sync-state pill top-right.
 */
function CategoryCard({
  title,
  hint = "Apri categoria",
  icon = null,
  syncLabel = null,
  syncTone = "green",
  onClick,
  style = {},
  ...rest
}) {
  const syncColors = {
    green: "var(--kb-cat-green)",
    orange: "var(--kb-warning)",
    red: "var(--kb-danger)"
  };
  return /*#__PURE__*/React.createElement("button", _extends({
    onClick: onClick,
    style: {
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
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("span", {
    style: {
      display: "flex",
      alignItems: "center",
      width: "100%"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--kb-text-secondary)",
      display: "inline-flex"
    }
  }, icon || /*#__PURE__*/React.createElement("svg", {
    width: "20",
    height: "20",
    viewBox: "0 0 24 24",
    fill: "currentColor"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M10 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-8l-2-2z"
  }))), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), syncLabel && /*#__PURE__*/React.createElement(__ds_scope.Chip, {
    tint: syncColors[syncTone],
    variant: "tinted"
  }, syncLabel)), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--kb-text-headline)",
      fontWeight: "var(--kb-weight-bold)",
      color: "var(--kb-text)"
    }
  }, title), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--kb-text-caption)",
      color: "var(--kb-text-secondary)"
    }
  }, hint));
}
Object.assign(__ds_scope, { CategoryCard });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/cards/CategoryCard.jsx", error: String((e && e.message) || e) }); }

// ui_kits/mobile-app/DocumentsScreen.jsx
try { (() => {
// DocumentsScreen — recreates Features/Documents/{DocumentsHomeView,DocumentFolderView}:
// grid of category folders with a sync-state pill (CategoryCard.swift).
const {
  CategoryCard
} = window.KidBoxDesignSystem_d1a58b;
const FOLDERS = [{
  title: "Referti medici",
  sync: "Sincronizzato",
  tone: "green"
}, {
  title: "Assicurazioni",
  sync: "Sincronizzato",
  tone: "green"
}, {
  title: "Scuola",
  sync: "In corso…",
  tone: "orange"
}, {
  title: "Contratti",
  sync: "Sincronizzato",
  tone: "green"
}, {
  title: "Veicoli",
  sync: "Sincronizzato",
  tone: "green"
}, {
  title: "Identità",
  sync: null
}];
function DocumentsScreen({
  onBack
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      height: "100%",
      overflowY: "auto",
      background: "var(--kb-bg)",
      fontFamily: "var(--kb-font-sans)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 10,
      padding: "16px 14px 6px"
    }
  }, /*#__PURE__*/React.createElement("button", {
    onClick: onBack,
    style: {
      background: "none",
      border: "none",
      color: "var(--kb-text)",
      display: "flex"
    }
  }, /*#__PURE__*/React.createElement(Ic, {
    name: "chevron-left",
    size: 22
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 28,
      fontWeight: 800,
      color: "var(--kb-text)"
    }
  }, "Documenti")), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 14,
      display: "grid",
      gridTemplateColumns: "1fr 1fr",
      gap: 12
    }
  }, FOLDERS.map(f => /*#__PURE__*/React.createElement(CategoryCard, {
    key: f.title,
    title: f.title,
    syncLabel: f.sync,
    syncTone: f.tone
  }))));
}
Object.assign(window, {
  DocumentsScreen
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/mobile-app/DocumentsScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/mobile-app/HomeScreen.jsx
try { (() => {
// HomeScreen — recreates Features/Home/HomeView.swift + HomeCardGrid:
// custom "KidBox" header + family switcher, HeroPhotoCard, 2-col category
// grid (full inventory + real tints/SF-Symbol mapping), InviteCard, AI FAB.
const {
  HomeCard,
  HeroCard,
  InviteCard,
  Badge,
  Chip
} = window.KidBoxDesignSystem_d1a58b;
const HOME_GRID = [{
  id: "note",
  title: "Note",
  subtitle: "Appunti veloci",
  tint: "var(--kb-cat-yellow)",
  icon: "sticky-note",
  badge: 2
}, {
  id: "todo",
  title: "To-Do",
  subtitle: "Lista condivisa",
  tint: "var(--kb-cat-blue)",
  icon: "list-checks"
}, {
  id: "shopping",
  title: "Lista della Spesa",
  subtitle: "Lista condivisa",
  tint: "var(--kb-cat-green)",
  icon: "shopping-cart"
}, {
  id: "calendar",
  title: "Calendario",
  subtitle: "Eventi e affidamenti",
  tint: "var(--kb-cat-purple)",
  icon: "calendar",
  badge: 1
}, {
  id: "care",
  title: "Salute",
  subtitle: "Health tracker",
  tint: "var(--kb-cat-red)",
  icon: "heart"
}, {
  id: "chat",
  title: "Chat",
  subtitle: "Messaggi famiglia",
  tint: "var(--kb-cat-green)",
  icon: "message-circle"
}, {
  id: "documents",
  title: "Documenti",
  subtitle: "Carte importanti",
  tint: "var(--kb-cat-orange)",
  icon: "file-text"
}, {
  id: "expenses",
  title: "Spese",
  subtitle: "Rette, visite, extra",
  tint: "var(--kb-cat-mint)",
  icon: "euro"
}, {
  id: "wallet",
  title: "Wallet",
  subtitle: "Biglietti e prenotazioni",
  tint: "var(--kb-cat-indigo)",
  icon: "ticket"
}, {
  id: "passwords",
  title: "Password",
  subtitle: "Credenziali di famiglia",
  tint: "var(--kb-cat-key)",
  icon: "key"
}, {
  id: "location",
  title: "Posizione",
  subtitle: "Dove sono tutti",
  tint: "var(--kb-cat-cyan)",
  icon: "map-pin"
}, {
  id: "photos",
  title: "Foto e video",
  subtitle: "Album condiviso",
  tint: "var(--kb-cat-pink)",
  icon: "images"
}, {
  id: "family",
  title: "Family",
  subtitle: "Membri e inviti",
  tint: "var(--kb-cat-teal)",
  icon: "users"
}, {
  id: "expert",
  title: "Assistente",
  subtitle: "Conosce salute, visite, documenti…",
  tint: "var(--kb-cat-purple)",
  icon: "brain"
}, {
  id: "travel",
  title: "Viaggi",
  subtitle: "Pianifica con l'AI",
  tint: "var(--kb-cat-teal)",
  icon: "briefcase"
}, {
  id: "pets",
  title: "Animali domestici",
  subtitle: "Cure e promemoria",
  tint: "var(--kb-cat-orange)",
  icon: "paw-print"
}, {
  id: "homeItems",
  title: "Casa",
  subtitle: "Garanzie e manutenzioni",
  tint: "var(--kb-cat-brown)",
  icon: "home"
}, {
  id: "vehicles",
  title: "Garage",
  subtitle: "Auto e scadenze",
  tint: "var(--kb-cat-ink)",
  icon: "car"
}];
function HomeScreen({
  onOpenSettings,
  onOpenCard
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      height: "100%",
      overflowY: "auto",
      background: "var(--kb-bg)",
      fontFamily: "var(--kb-font-sans)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "4px 14px 100px",
      display: "flex",
      flexDirection: "column",
      gap: 14
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 8,
      paddingTop: 4
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 2,
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 34,
      fontWeight: 800,
      letterSpacing: "-0.5px",
      color: "var(--kb-text)"
    }
  }, "KidBox"), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 15,
      fontWeight: 500,
      color: "var(--kb-text-secondary)"
    }
  }, "Famiglia Scocca")), /*#__PURE__*/React.createElement("button", {
    style: {
      width: 40,
      height: 40,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      background: "none",
      border: "none",
      color: "var(--kb-text)"
    }
  }, /*#__PURE__*/React.createElement(Ic, {
    name: "arrow-left-right",
    size: 18
  }))), /*#__PURE__*/React.createElement(HeroCard, {
    title: "Famiglia Scocca",
    dateText: "luned\xEC, 6 luglio",
    badgeText: "4 membri"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "grid",
      gridTemplateColumns: "1fr 1fr",
      gap: 12
    }
  }, HOME_GRID.map(c => /*#__PURE__*/React.createElement(HomeCard, {
    key: c.id,
    title: c.title,
    subtitle: c.subtitle,
    tint: c.tint,
    badge: c.badge || 0,
    icon: /*#__PURE__*/React.createElement(Ic, {
      name: c.icon,
      size: 22
    }),
    onClick: () => onOpenCard && onOpenCard(c.id)
  }))), /*#__PURE__*/React.createElement(InviteCard, null)), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "fixed",
      right: 20,
      bottom: 32
    }
  }, /*#__PURE__*/React.createElement(window.KidBoxDesignSystem_d1a58b.AskAIButton, null)), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: 14,
      left: 14,
      right: 14,
      display: "flex",
      justifyContent: "space-between",
      pointerEvents: "none"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 34,
      height: 34,
      borderRadius: "50%",
      background: "var(--kb-orange-soft)",
      pointerEvents: "auto"
    }
  }), /*#__PURE__*/React.createElement("button", {
    onClick: onOpenSettings,
    style: {
      pointerEvents: "auto",
      background: "none",
      border: "none",
      color: "var(--kb-text)"
    }
  }, /*#__PURE__*/React.createElement(Ic, {
    name: "settings",
    size: 20
  }))));
}
Object.assign(window, {
  HomeScreen
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/mobile-app/HomeScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/mobile-app/Icons.jsx
try { (() => {
// Shared icon helper for the KidBox mobile-app UI kit.
//
// The real apps use SF Symbols (iOS, proprietary/unshippable) and Android's
// Material icon set. Neither ships as files we can copy into a web project,
// so this kit substitutes Lucide (github.com/lucide-icons/lucide) — closest
// match in stroke weight (~1.8px) and rounded-line style — loaded from CDN in
// index.html. Flagged here and in the design system readme.
function Ic({
  name,
  size = 20,
  color,
  style = {}
}) {
  const ref = React.useRef(null);
  React.useEffect(() => {
    if (window.lucide) window.lucide.createIcons();
  });
  return /*#__PURE__*/React.createElement("i", {
    ref: ref,
    "data-lucide": name,
    style: {
      width: size,
      height: size,
      color: color || "currentColor",
      display: "inline-flex",
      flexShrink: 0,
      ...style
    }
  });
}
Object.assign(window, {
  Ic
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/mobile-app/Icons.jsx", error: String((e && e.message) || e) }); }

// ui_kits/mobile-app/LoginScreen.jsx
try { (() => {
// LoginScreen — recreates Features/Auth/LoginView.swift:
// logo + serif hero title/tagline, Google/Apple/Facebook provider pills,
// "o" divider, outlined email pill, legal footer with linked terms/privacy.
function LoginScreen({
  onLogin
}) {
  const [busy, setBusy] = React.useState(false);
  const go = () => {
    setBusy(true);
    setTimeout(() => {
      setBusy(false);
      onLogin();
    }, 700);
  };
  const providerBtn = (label, icon) => /*#__PURE__*/React.createElement("button", {
    onClick: go,
    disabled: busy,
    style: {
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      gap: 10,
      height: 52,
      borderRadius: 999,
      border: "none",
      background: "var(--kb-btn-primary-bg)",
      color: "var(--kb-btn-primary-fg)",
      fontFamily: "var(--kb-font-sans)",
      fontSize: 16,
      fontWeight: 700,
      opacity: busy ? 0.6 : 1,
      cursor: busy ? "default" : "pointer"
    }
  }, icon, label);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: "relative",
      height: "100%",
      overflowY: "auto",
      background: "var(--kb-bg)",
      fontFamily: "var(--kb-font-sans)",
      padding: "72px 28px 40px"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      alignItems: "center",
      gap: 16,
      marginBottom: 52
    }
  }, /*#__PURE__*/React.createElement("img", {
    src: "../../assets/kidbox-icon.png",
    alt: "KidBox",
    style: {
      width: 52,
      height: 52,
      borderRadius: 12
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: "var(--kb-font-serif-display)",
      fontSize: 36,
      fontWeight: 600,
      color: "var(--kb-text)"
    }
  }, "KidBox"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: "var(--kb-font-serif-display)",
      fontSize: 26,
      fontWeight: 500,
      color: "var(--kb-text)",
      textAlign: "center",
      lineHeight: 1.3
    }
  }, "La tua famiglia,", /*#__PURE__*/React.createElement("br", null), "in un'unica app.")), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 12,
      marginBottom: 20
    }
  }, providerBtn("Continua con Google", /*#__PURE__*/React.createElement("span", {
    style: {
      width: 22,
      height: 22,
      borderRadius: "50%",
      background: "#fff",
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      fontSize: 13,
      fontWeight: 800,
      color: "#4285F4"
    }
  }, "G")), providerBtn("Continua con Apple", /*#__PURE__*/React.createElement(Ic, {
    name: "apple",
    size: 18
  })), providerBtn("Continua con Facebook", /*#__PURE__*/React.createElement("span", {
    style: {
      width: 22,
      height: 22,
      borderRadius: "50%",
      background: "#3B5998",
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      fontSize: 14,
      fontWeight: 800,
      color: "#fff"
    }
  }, "f"))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 12,
      margin: "20px 0"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      height: 1,
      background: "rgba(0,0,0,0.15)"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      width: 24,
      height: 24,
      borderRadius: "50%",
      border: "1px solid rgba(0,0,0,0.2)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontSize: 11,
      color: "var(--kb-text-secondary)"
    }
  }, "o"), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      height: 1,
      background: "rgba(0,0,0,0.15)"
    }
  })), /*#__PURE__*/React.createElement("button", {
    onClick: go,
    style: {
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      gap: 10,
      width: "100%",
      height: 52,
      borderRadius: 999,
      border: "1.5px solid rgba(0,0,0,0.25)",
      background: "transparent",
      fontFamily: "var(--kb-font-sans)",
      fontSize: 16,
      fontWeight: 700,
      color: "var(--kb-text)"
    }
  }, /*#__PURE__*/React.createElement(Ic, {
    name: "mail",
    size: 16
  }), "Continua con email"), /*#__PURE__*/React.createElement("p", {
    style: {
      marginTop: 32,
      textAlign: "center",
      fontSize: 12,
      color: "var(--kb-text-secondary)",
      lineHeight: 1.5
    }
  }, "Continuando, accetti i ", /*#__PURE__*/React.createElement("u", null, "Termini di Servizio"), " e la ", /*#__PURE__*/React.createElement("u", null, "Privacy Policy"), " di KidBox."), busy && /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      inset: 0,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      background: "rgba(0,0,0,0.05)",
      backdropFilter: "blur(1px)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      alignItems: "center",
      gap: 10,
      padding: 16,
      borderRadius: 14,
      background: "rgba(255,255,255,0.7)",
      backdropFilter: "blur(20px)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 20,
      height: 20,
      border: "2.5px solid rgba(0,0,0,0.2)",
      borderTopColor: "var(--kb-text)",
      borderRadius: "50%",
      animation: "kbSpin 0.8s linear infinite"
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 14,
      fontWeight: 500
    }
  }, "Accesso in corso\u2026"))), /*#__PURE__*/React.createElement("style", null, `@keyframes kbSpin{to{transform:rotate(360deg)}}`));
}
Object.assign(window, {
  LoginScreen
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/mobile-app/LoginScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/mobile-app/SettingsScreen.jsx
try { (() => {
// SettingsScreen — recreates Features/Settings/SettingsView/SettingsView.swift:
// icon+title(+caption) rows tinted with KBTheme.bubbleTint, version footer.
const {
  SettingsCard
} = window.KidBoxDesignSystem_d1a58b;
const ROWS = [{
  title: "Tema",
  subtitle: "Sistema",
  icon: "sun"
}, {
  title: "Family settings",
  icon: "users"
}, {
  title: "Messaggi",
  icon: "message-circle"
}, {
  title: "Assistente AI",
  icon: "sparkles"
}, {
  title: "Notifiche",
  icon: "bell"
}, {
  title: "Privacy",
  subtitle: "Report errori e log tecnici",
  icon: "hand"
}, {
  title: "Password",
  subtitle: "AutoFill e compilazione automatica",
  icon: "key"
}, {
  title: "Utilizzo spazio",
  icon: "hard-drive"
}, {
  title: "Assistente & Supporto",
  subtitle: "Domande, problemi e suggerimenti",
  icon: "life-buoy"
}];
function SettingsScreen({
  onBack
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      height: "100%",
      overflowY: "auto",
      background: "var(--kb-bg)",
      fontFamily: "var(--kb-font-sans)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 10,
      padding: "16px 14px 6px"
    }
  }, /*#__PURE__*/React.createElement("button", {
    onClick: onBack,
    style: {
      background: "none",
      border: "none",
      color: "var(--kb-text)",
      display: "flex"
    }
  }, /*#__PURE__*/React.createElement(Ic, {
    name: "chevron-left",
    size: 22
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 28,
      fontWeight: 800,
      color: "var(--kb-text)"
    }
  }, "Impostazioni")), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "10px 14px",
      display: "flex",
      flexDirection: "column",
      gap: 8
    }
  }, ROWS.map(r => /*#__PURE__*/React.createElement(SettingsCard, {
    key: r.title,
    title: r.title,
    subtitle: r.subtitle,
    tone: "primary",
    icon: /*#__PURE__*/React.createElement(Ic, {
      name: r.icon,
      size: 19,
      color: "var(--kb-orange-bubble)"
    }),
    trailing: /*#__PURE__*/React.createElement(Ic, {
      name: "chevron-right",
      size: 16,
      color: "var(--kb-text-secondary)"
    })
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      textAlign: "center",
      padding: "16px 0 28px",
      color: "var(--kb-text-secondary)",
      fontSize: 12,
      lineHeight: 1.6
    }
  }, "Versione 1.0", /*#__PURE__*/React.createElement("br", null), "Build 42"));
}
Object.assign(window, {
  SettingsScreen
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/mobile-app/SettingsScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/mobile-app/ios-frame.jsx
try { (() => {
// @ds-adherence-ignore -- omelette starter scaffold (raw elements/hex/px by design)

/* BEGIN USAGE */
// iOS.jsx — Simplified iOS 26 (Liquid Glass) device frame
// Based on the iOS 26 UI Kit + Figma status bar spec. No assets, no deps.
// Exports (to window): IOSDevice, IOSStatusBar, IOSNavBar, IOSGlassPill, IOSList, IOSListRow, IOSKeyboard
//
// Usage — wrap your screen content in <IOSDevice> to get the bezel, status bar
// and home indicator (props: title, dark, keyboard):
//
//   <IOSDevice title="Settings">
//     ...your screen content...
//   </IOSDevice>
//   <IOSDevice dark title="Search" keyboard>…</IOSDevice>
/* END USAGE */

// ─────────────────────────────────────────────────────────────
// Status bar
// ─────────────────────────────────────────────────────────────
function IOSStatusBar({
  dark = false,
  time = '9:41'
}) {
  const c = dark ? '#fff' : '#000';
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 154,
      alignItems: 'center',
      justifyContent: 'center',
      padding: '21px 24px 19px',
      boxSizing: 'border-box',
      position: 'relative',
      zIndex: 20,
      width: '100%'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      height: 22,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      paddingTop: 1.5
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: '-apple-system, "SF Pro", system-ui',
      fontWeight: 590,
      fontSize: 17,
      lineHeight: '22px',
      color: c
    }
  }, time)), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      height: 22,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 7,
      paddingTop: 1,
      paddingRight: 1
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: "19",
    height: "12",
    viewBox: "0 0 19 12"
  }, /*#__PURE__*/React.createElement("rect", {
    x: "0",
    y: "7.5",
    width: "3.2",
    height: "4.5",
    rx: "0.7",
    fill: c
  }), /*#__PURE__*/React.createElement("rect", {
    x: "4.8",
    y: "5",
    width: "3.2",
    height: "7",
    rx: "0.7",
    fill: c
  }), /*#__PURE__*/React.createElement("rect", {
    x: "9.6",
    y: "2.5",
    width: "3.2",
    height: "9.5",
    rx: "0.7",
    fill: c
  }), /*#__PURE__*/React.createElement("rect", {
    x: "14.4",
    y: "0",
    width: "3.2",
    height: "12",
    rx: "0.7",
    fill: c
  })), /*#__PURE__*/React.createElement("svg", {
    width: "17",
    height: "12",
    viewBox: "0 0 17 12"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M8.5 3.2C10.8 3.2 12.9 4.1 14.4 5.6L15.5 4.5C13.7 2.7 11.2 1.5 8.5 1.5C5.8 1.5 3.3 2.7 1.5 4.5L2.6 5.6C4.1 4.1 6.2 3.2 8.5 3.2Z",
    fill: c
  }), /*#__PURE__*/React.createElement("path", {
    d: "M8.5 6.8C9.9 6.8 11.1 7.3 12 8.2L13.1 7.1C11.8 5.9 10.2 5.1 8.5 5.1C6.8 5.1 5.2 5.9 3.9 7.1L5 8.2C5.9 7.3 7.1 6.8 8.5 6.8Z",
    fill: c
  }), /*#__PURE__*/React.createElement("circle", {
    cx: "8.5",
    cy: "10.5",
    r: "1.5",
    fill: c
  })), /*#__PURE__*/React.createElement("svg", {
    width: "27",
    height: "13",
    viewBox: "0 0 27 13"
  }, /*#__PURE__*/React.createElement("rect", {
    x: "0.5",
    y: "0.5",
    width: "23",
    height: "12",
    rx: "3.5",
    stroke: c,
    strokeOpacity: "0.35",
    fill: "none"
  }), /*#__PURE__*/React.createElement("rect", {
    x: "2",
    y: "2",
    width: "20",
    height: "9",
    rx: "2",
    fill: c
  }), /*#__PURE__*/React.createElement("path", {
    d: "M25 4.5V8.5C25.8 8.2 26.5 7.2 26.5 6.5C26.5 5.8 25.8 4.8 25 4.5Z",
    fill: c,
    fillOpacity: "0.4"
  }))));
}

// ─────────────────────────────────────────────────────────────
// Liquid glass pill — blur + tint + shine
// ─────────────────────────────────────────────────────────────
function IOSGlassPill({
  children,
  dark = false,
  style = {}
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      height: 44,
      minWidth: 44,
      borderRadius: 9999,
      position: 'relative',
      overflow: 'hidden',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      boxShadow: dark ? '0 2px 6px rgba(0,0,0,0.35), 0 6px 16px rgba(0,0,0,0.2)' : '0 1px 3px rgba(0,0,0,0.07), 0 3px 10px rgba(0,0,0,0.06)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      borderRadius: 9999,
      backdropFilter: 'blur(12px) saturate(180%)',
      WebkitBackdropFilter: 'blur(12px) saturate(180%)',
      background: dark ? 'rgba(120,120,128,0.28)' : 'rgba(255,255,255,0.5)'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      borderRadius: 9999,
      boxShadow: dark ? 'inset 1.5px 1.5px 1px rgba(255,255,255,0.15), inset -1px -1px 1px rgba(255,255,255,0.08)' : 'inset 1.5px 1.5px 1px rgba(255,255,255,0.7), inset -1px -1px 1px rgba(255,255,255,0.4)',
      border: dark ? '0.5px solid rgba(255,255,255,0.15)' : '0.5px solid rgba(0,0,0,0.06)'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      zIndex: 1,
      display: 'flex',
      alignItems: 'center',
      padding: '0 4px'
    }
  }, children));
}

// ─────────────────────────────────────────────────────────────
// Navigation bar — glass pills + large title
// ─────────────────────────────────────────────────────────────
function IOSNavBar({
  title = 'Title',
  dark = false,
  trailingIcon = true
}) {
  const muted = dark ? 'rgba(255,255,255,0.6)' : '#404040';
  const text = dark ? '#fff' : '#000';
  const pillIcon = content => /*#__PURE__*/React.createElement(IOSGlassPill, {
    dark: dark
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 36,
      height: 36,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center'
    }
  }, content));
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 10,
      paddingTop: 62,
      paddingBottom: 10,
      position: 'relative',
      zIndex: 5
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '0 16px'
    }
  }, pillIcon(/*#__PURE__*/React.createElement("svg", {
    width: "12",
    height: "20",
    viewBox: "0 0 12 20",
    fill: "none",
    style: {
      marginLeft: -1
    }
  }, /*#__PURE__*/React.createElement("path", {
    d: "M10 2L2 10l8 8",
    stroke: muted,
    strokeWidth: "2.5",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }))), trailingIcon && pillIcon(/*#__PURE__*/React.createElement("svg", {
    width: "22",
    height: "6",
    viewBox: "0 0 22 6"
  }, /*#__PURE__*/React.createElement("circle", {
    cx: "3",
    cy: "3",
    r: "2.5",
    fill: muted
  }), /*#__PURE__*/React.createElement("circle", {
    cx: "11",
    cy: "3",
    r: "2.5",
    fill: muted
  }), /*#__PURE__*/React.createElement("circle", {
    cx: "19",
    cy: "3",
    r: "2.5",
    fill: muted
  })))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 16px',
      fontFamily: '-apple-system, system-ui',
      fontSize: 34,
      fontWeight: 700,
      lineHeight: '41px',
      color: text,
      letterSpacing: 0.4
    }
  }, title));
}

// ─────────────────────────────────────────────────────────────
// Grouped list (inset card, r:26) + row (52px)
// ─────────────────────────────────────────────────────────────
function IOSListRow({
  title,
  detail,
  icon,
  chevron = true,
  isLast = false,
  dark = false
}) {
  const text = dark ? '#fff' : '#000';
  const sec = dark ? 'rgba(235,235,245,0.6)' : 'rgba(60,60,67,0.6)';
  const ter = dark ? 'rgba(235,235,245,0.3)' : 'rgba(60,60,67,0.3)';
  const sep = dark ? 'rgba(84,84,88,0.65)' : 'rgba(60,60,67,0.12)';
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      minHeight: 52,
      padding: '0 16px',
      position: 'relative',
      fontFamily: '-apple-system, system-ui',
      fontSize: 17,
      letterSpacing: -0.43
    }
  }, icon && /*#__PURE__*/React.createElement("div", {
    style: {
      width: 30,
      height: 30,
      borderRadius: 7,
      background: icon,
      marginRight: 12,
      flexShrink: 0
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      color: text
    }
  }, title), detail && /*#__PURE__*/React.createElement("span", {
    style: {
      color: sec,
      marginRight: 6
    }
  }, detail), chevron && /*#__PURE__*/React.createElement("svg", {
    width: "8",
    height: "14",
    viewBox: "0 0 8 14",
    style: {
      flexShrink: 0
    }
  }, /*#__PURE__*/React.createElement("path", {
    d: "M1 1l6 6-6 6",
    stroke: ter,
    strokeWidth: "2",
    fill: "none",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  })), !isLast && /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      bottom: 0,
      right: 0,
      left: icon ? 58 : 16,
      height: 0.5,
      background: sep
    }
  }));
}
function IOSList({
  header,
  children,
  dark = false
}) {
  const hc = dark ? 'rgba(235,235,245,0.6)' : 'rgba(60,60,67,0.6)';
  const bg = dark ? '#1C1C1E' : '#fff';
  return /*#__PURE__*/React.createElement("div", null, header && /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: '-apple-system, system-ui',
      fontSize: 13,
      color: hc,
      textTransform: 'uppercase',
      padding: '8px 36px 6px',
      letterSpacing: -0.08
    }
  }, header), /*#__PURE__*/React.createElement("div", {
    style: {
      background: bg,
      borderRadius: 26,
      margin: '0 16px',
      overflow: 'hidden'
    }
  }, children));
}

// ─────────────────────────────────────────────────────────────
// Device frame
// ─────────────────────────────────────────────────────────────
function IOSDevice({
  children,
  width = 402,
  height = 874,
  dark = false,
  title,
  keyboard = false
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      width,
      height,
      borderRadius: 48,
      overflow: 'hidden',
      position: 'relative',
      background: dark ? '#000' : '#F2F2F7',
      boxShadow: '0 40px 80px rgba(0,0,0,0.18), 0 0 0 1px rgba(0,0,0,0.12)',
      fontFamily: '-apple-system, system-ui, sans-serif',
      WebkitFontSmoothing: 'antialiased'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      top: 11,
      left: '50%',
      transform: 'translateX(-50%)',
      width: 126,
      height: 37,
      borderRadius: 24,
      background: '#000',
      zIndex: 50
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      top: 0,
      left: 0,
      right: 0,
      zIndex: 10
    }
  }, /*#__PURE__*/React.createElement(IOSStatusBar, {
    dark: dark
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      height: '100%',
      display: 'flex',
      flexDirection: 'column'
    }
  }, title !== undefined && /*#__PURE__*/React.createElement(IOSNavBar, {
    title: title,
    dark: dark
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflow: 'auto'
    }
  }, children), keyboard && /*#__PURE__*/React.createElement(IOSKeyboard, {
    dark: dark
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      bottom: 0,
      left: 0,
      right: 0,
      zIndex: 60,
      height: 34,
      display: 'flex',
      justifyContent: 'center',
      alignItems: 'flex-end',
      paddingBottom: 8,
      pointerEvents: 'none'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 139,
      height: 5,
      borderRadius: 100,
      background: dark ? 'rgba(255,255,255,0.7)' : 'rgba(0,0,0,0.25)'
    }
  })));
}

// ─────────────────────────────────────────────────────────────
// Keyboard — iOS 26 liquid glass
// ─────────────────────────────────────────────────────────────
function IOSKeyboard({
  dark = false
}) {
  const glyph = dark ? 'rgba(255,255,255,0.7)' : '#595959';
  const sugg = dark ? 'rgba(255,255,255,0.6)' : '#333';
  const keyBg = dark ? 'rgba(255,255,255,0.22)' : 'rgba(255,255,255,0.85)';

  // special-key icons
  const icons = {
    shift: /*#__PURE__*/React.createElement("svg", {
      width: "19",
      height: "17",
      viewBox: "0 0 19 17"
    }, /*#__PURE__*/React.createElement("path", {
      d: "M9.5 1L1 9.5h4.5V16h8V9.5H18L9.5 1z",
      fill: glyph
    })),
    del: /*#__PURE__*/React.createElement("svg", {
      width: "23",
      height: "17",
      viewBox: "0 0 23 17"
    }, /*#__PURE__*/React.createElement("path", {
      d: "M7 1h13a2 2 0 012 2v11a2 2 0 01-2 2H7l-6-7.5L7 1z",
      fill: "none",
      stroke: glyph,
      strokeWidth: "1.6",
      strokeLinejoin: "round"
    }), /*#__PURE__*/React.createElement("path", {
      d: "M10 5l7 7M17 5l-7 7",
      stroke: glyph,
      strokeWidth: "1.6",
      strokeLinecap: "round"
    })),
    ret: /*#__PURE__*/React.createElement("svg", {
      width: "20",
      height: "14",
      viewBox: "0 0 20 14"
    }, /*#__PURE__*/React.createElement("path", {
      d: "M18 1v6H4m0 0l4-4M4 7l4 4",
      fill: "none",
      stroke: "#fff",
      strokeWidth: "1.8",
      strokeLinecap: "round",
      strokeLinejoin: "round"
    }))
  };
  const key = (content, {
    w,
    flex,
    ret,
    fs = 25,
    k
  } = {}) => /*#__PURE__*/React.createElement("div", {
    key: k,
    style: {
      height: 42,
      borderRadius: 8.5,
      flex: flex ? 1 : undefined,
      width: w,
      minWidth: 0,
      background: ret ? '#08f' : keyBg,
      boxShadow: '0 1px 0 rgba(0,0,0,0.075)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      fontFamily: '-apple-system, "SF Compact", system-ui',
      fontSize: fs,
      fontWeight: 458,
      color: ret ? '#fff' : glyph
    }
  }, content);
  const row = (keys, pad = 0) => /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 6.5,
      justifyContent: 'center',
      padding: `0 ${pad}px`
    }
  }, keys.map(l => key(l, {
    flex: true,
    k: l
  })));
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      zIndex: 15,
      borderRadius: 27,
      overflow: 'hidden',
      padding: '11px 0 2px',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      boxShadow: dark ? '0 -2px 20px rgba(0,0,0,0.09)' : '0 -1px 6px rgba(0,0,0,0.018), 0 -3px 20px rgba(0,0,0,0.012)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      borderRadius: 27,
      backdropFilter: 'blur(12px) saturate(180%)',
      WebkitBackdropFilter: 'blur(12px) saturate(180%)',
      background: dark ? 'rgba(120,120,128,0.14)' : 'rgba(255,255,255,0.25)'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      borderRadius: 27,
      boxShadow: dark ? 'inset 1.5px 1.5px 1px rgba(255,255,255,0.15)' : 'inset 1.5px 1.5px 1px rgba(255,255,255,0.7), inset -1px -1px 1px rgba(255,255,255,0.4)',
      border: dark ? '0.5px solid rgba(255,255,255,0.15)' : '0.5px solid rgba(0,0,0,0.06)',
      pointerEvents: 'none'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 20,
      alignItems: 'center',
      padding: '8px 22px 13px',
      width: '100%',
      boxSizing: 'border-box',
      position: 'relative'
    }
  }, ['"The"', 'the', 'to'].map((w, i) => /*#__PURE__*/React.createElement(React.Fragment, {
    key: i
  }, i > 0 && /*#__PURE__*/React.createElement("div", {
    style: {
      width: 1,
      height: 25,
      background: '#ccc',
      opacity: 0.3
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      textAlign: 'center',
      fontFamily: '-apple-system, system-ui',
      fontSize: 17,
      color: sugg,
      letterSpacing: -0.43,
      lineHeight: '22px'
    }
  }, w)))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 13,
      padding: '0 6.5px',
      width: '100%',
      boxSizing: 'border-box',
      position: 'relative'
    }
  }, row(['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p']), row(['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'], 20), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 14.25,
      alignItems: 'center'
    }
  }, key(icons.shift, {
    w: 45,
    k: 'shift'
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 6.5,
      flex: 1
    }
  }, ['z', 'x', 'c', 'v', 'b', 'n', 'm'].map(l => key(l, {
    flex: true,
    k: l
  }))), key(icons.del, {
    w: 45,
    k: 'del'
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 6,
      alignItems: 'center'
    }
  }, key('ABC', {
    w: 92.25,
    fs: 18,
    k: 'abc'
  }), key('', {
    flex: true,
    k: 'space'
  }), key(icons.ret, {
    w: 92.25,
    ret: true,
    k: 'ret'
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 56,
      width: '100%',
      position: 'relative'
    }
  }));
}
Object.assign(window, {
  IOSDevice,
  IOSStatusBar,
  IOSNavBar,
  IOSGlassPill,
  IOSList,
  IOSListRow,
  IOSKeyboard
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/mobile-app/ios-frame.jsx", error: String((e && e.message) || e) }); }

__ds_ns.AskAIButton = __ds_scope.AskAIButton;

__ds_ns.CategoryCard = __ds_scope.CategoryCard;

__ds_ns.HeroCard = __ds_scope.HeroCard;

__ds_ns.HomeCard = __ds_scope.HomeCard;

__ds_ns.InviteCard = __ds_scope.InviteCard;

__ds_ns.SettingsCard = __ds_scope.SettingsCard;

__ds_ns.Avatar = __ds_scope.Avatar;

__ds_ns.Badge = __ds_scope.Badge;

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Chip = __ds_scope.Chip;

})();
