// Shared icon helper for the KidBox mobile-app UI kit.
//
// The real apps use SF Symbols (iOS, proprietary/unshippable) and Android's
// Material icon set. Neither ships as files we can copy into a web project,
// so this kit substitutes Lucide (github.com/lucide-icons/lucide) — closest
// match in stroke weight (~1.8px) and rounded-line style — loaded from CDN in
// index.html. Flagged here and in the design system readme.
function Ic({ name, size = 20, color, style = {} }) {
  const ref = React.useRef(null);
  React.useEffect(() => {
    if (window.lucide) window.lucide.createIcons();
  });
  return (
    <i
      ref={ref}
      data-lucide={name}
      style={{ width: size, height: size, color: color || "currentColor", display: "inline-flex", flexShrink: 0, ...style }}
    ></i>
  );
}

Object.assign(window, { Ic });
