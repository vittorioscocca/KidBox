// DocumentsScreen — recreates Features/Documents/{DocumentsHomeView,DocumentFolderView}:
// grid of category folders with a sync-state pill (CategoryCard.swift).
const { CategoryCard } = window.KidBoxDesignSystem_d1a58b;

const FOLDERS = [
  { title: "Referti medici", sync: "Sincronizzato", tone: "green" },
  { title: "Assicurazioni", sync: "Sincronizzato", tone: "green" },
  { title: "Scuola", sync: "In corso…", tone: "orange" },
  { title: "Contratti", sync: "Sincronizzato", tone: "green" },
  { title: "Veicoli", sync: "Sincronizzato", tone: "green" },
  { title: "Identità", sync: null },
];

function DocumentsScreen({ onBack }) {
  return (
    <div style={{ height: "100%", overflowY: "auto", background: "var(--kb-bg)", fontFamily: "var(--kb-font-sans)" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "16px 14px 6px" }}>
        <button onClick={onBack} style={{ background: "none", border: "none", color: "var(--kb-text)", display: "flex" }}>
          <Ic name="chevron-left" size={22} />
        </button>
        <span style={{ fontSize: 28, fontWeight: 800, color: "var(--kb-text)" }}>Documenti</span>
      </div>
      <div style={{ padding: 14, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
        {FOLDERS.map((f) => (
          <CategoryCard key={f.title} title={f.title} syncLabel={f.sync} syncTone={f.tone} />
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { DocumentsScreen });
