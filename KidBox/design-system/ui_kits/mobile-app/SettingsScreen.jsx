// SettingsScreen — recreates Features/Settings/SettingsView/SettingsView.swift:
// icon+title(+caption) rows tinted with KBTheme.bubbleTint, version footer.
const { SettingsCard } = window.KidBoxDesignSystem_d1a58b;

const ROWS = [
  { title: "Tema", subtitle: "Sistema", icon: "sun" },
  { title: "Family settings", icon: "users" },
  { title: "Messaggi", icon: "message-circle" },
  { title: "Assistente AI", icon: "sparkles" },
  { title: "Notifiche", icon: "bell" },
  { title: "Privacy", subtitle: "Report errori e log tecnici", icon: "hand" },
  { title: "Password", subtitle: "AutoFill e compilazione automatica", icon: "key" },
  { title: "Utilizzo spazio", icon: "hard-drive" },
  { title: "Assistente & Supporto", subtitle: "Domande, problemi e suggerimenti", icon: "life-buoy" },
];

function SettingsScreen({ onBack }) {
  return (
    <div style={{ height: "100%", overflowY: "auto", background: "var(--kb-bg)", fontFamily: "var(--kb-font-sans)" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "16px 14px 6px" }}>
        <button onClick={onBack} style={{ background: "none", border: "none", color: "var(--kb-text)", display: "flex" }}>
          <Ic name="chevron-left" size={22} />
        </button>
        <span style={{ fontSize: 28, fontWeight: 800, color: "var(--kb-text)" }}>Impostazioni</span>
      </div>

      <div style={{ padding: "10px 14px", display: "flex", flexDirection: "column", gap: 8 }}>
        {ROWS.map((r) => (
          <SettingsCard
            key={r.title}
            title={r.title}
            subtitle={r.subtitle}
            tone="primary"
            icon={<Ic name={r.icon} size={19} color="var(--kb-orange-bubble)" />}
            trailing={<Ic name="chevron-right" size={16} color="var(--kb-text-secondary)" />}
          />
        ))}
      </div>

      <div style={{ textAlign: "center", padding: "16px 0 28px", color: "var(--kb-text-secondary)", fontSize: 12, lineHeight: 1.6 }}>
        Versione 1.0<br />Build 42
      </div>
    </div>
  );
}

Object.assign(window, { SettingsScreen });
