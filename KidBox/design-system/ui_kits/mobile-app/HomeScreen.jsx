// HomeScreen — recreates Features/Home/HomeView.swift + HomeCardGrid:
// custom "KidBox" header + family switcher, HeroPhotoCard, 2-col category
// grid (full inventory + real tints/SF-Symbol mapping), InviteCard, AI FAB.
const { HomeCard, HeroCard, InviteCard, Badge, Chip } = window.KidBoxDesignSystem_d1a58b;

const HOME_GRID = [
  { id: "note", title: "Note", subtitle: "Appunti veloci", tint: "var(--kb-cat-yellow)", icon: "sticky-note", badge: 2 },
  { id: "todo", title: "To-Do", subtitle: "Lista condivisa", tint: "var(--kb-cat-blue)", icon: "list-checks" },
  { id: "shopping", title: "Lista della Spesa", subtitle: "Lista condivisa", tint: "var(--kb-cat-green)", icon: "shopping-cart" },
  { id: "calendar", title: "Calendario", subtitle: "Eventi e affidamenti", tint: "var(--kb-cat-purple)", icon: "calendar", badge: 1 },
  { id: "care", title: "Salute", subtitle: "Health tracker", tint: "var(--kb-cat-red)", icon: "heart" },
  { id: "chat", title: "Chat", subtitle: "Messaggi famiglia", tint: "var(--kb-cat-green)", icon: "message-circle" },
  { id: "documents", title: "Documenti", subtitle: "Carte importanti", tint: "var(--kb-cat-orange)", icon: "file-text" },
  { id: "expenses", title: "Spese", subtitle: "Rette, visite, extra", tint: "var(--kb-cat-mint)", icon: "euro" },
  { id: "wallet", title: "Wallet", subtitle: "Biglietti e prenotazioni", tint: "var(--kb-cat-indigo)", icon: "ticket" },
  { id: "passwords", title: "Password", subtitle: "Credenziali di famiglia", tint: "var(--kb-cat-key)", icon: "key" },
  { id: "location", title: "Posizione", subtitle: "Dove sono tutti", tint: "var(--kb-cat-cyan)", icon: "map-pin" },
  { id: "photos", title: "Foto e video", subtitle: "Album condiviso", tint: "var(--kb-cat-pink)", icon: "images" },
  { id: "family", title: "Family", subtitle: "Membri e inviti", tint: "var(--kb-cat-teal)", icon: "users" },
  { id: "expert", title: "Assistente", subtitle: "Conosce salute, visite, documenti…", tint: "var(--kb-cat-purple)", icon: "brain" },
  { id: "travel", title: "Viaggi", subtitle: "Pianifica con l'AI", tint: "var(--kb-cat-teal)", icon: "briefcase" },
  { id: "pets", title: "Animali domestici", subtitle: "Cure e promemoria", tint: "var(--kb-cat-orange)", icon: "paw-print" },
  { id: "homeItems", title: "Casa", subtitle: "Garanzie e manutenzioni", tint: "var(--kb-cat-brown)", icon: "home" },
  { id: "vehicles", title: "Garage", subtitle: "Auto e scadenze", tint: "var(--kb-cat-ink)", icon: "car" },
];

function HomeScreen({ onOpenSettings, onOpenCard }) {
  return (
    <div style={{ height: "100%", overflowY: "auto", background: "var(--kb-bg)", fontFamily: "var(--kb-font-sans)" }}>
      <div style={{ padding: "4px 14px 100px", display: "flex", flexDirection: "column", gap: 14 }}>

        {/* Header */}
        <div style={{ display: "flex", alignItems: "center", gap: 8, paddingTop: 4 }}>
          <div style={{ display: "flex", flexDirection: "column", gap: 2, flex: 1, minWidth: 0 }}>
            <span style={{ fontSize: 34, fontWeight: 800, letterSpacing: "-0.5px", color: "var(--kb-text)" }}>KidBox</span>
            <span style={{ fontSize: 15, fontWeight: 500, color: "var(--kb-text-secondary)" }}>Famiglia Scocca</span>
          </div>
          <button style={{ width: 40, height: 40, display: "flex", alignItems: "center", justifyContent: "center", background: "none", border: "none", color: "var(--kb-text)" }}>
            <Ic name="arrow-left-right" size={18} />
          </button>
        </div>

        {/* Hero */}
        <HeroCard title="Famiglia Scocca" dateText="lunedì, 6 luglio" badgeText="4 membri" />

        {/* Grid */}
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
          {HOME_GRID.map((c) => (
            <HomeCard
              key={c.id}
              title={c.title}
              subtitle={c.subtitle}
              tint={c.tint}
              badge={c.badge || 0}
              icon={<Ic name={c.icon} size={22} />}
              onClick={() => onOpenCard && onOpenCard(c.id)}
            />
          ))}
        </div>

        <InviteCard />
      </div>

      {/* AI FAB */}
      <div style={{ position: "fixed", right: 20, bottom: 32 }}>
        <window.KidBoxDesignSystem_d1a58b.AskAIButton />
      </div>

      {/* top bar overlay: avatar + settings gear (mimics the SwiftUI toolbar) */}
      <div style={{ position: "absolute", top: 14, left: 14, right: 14, display: "flex", justifyContent: "space-between", pointerEvents: "none" }}>
        <div style={{ width: 34, height: 34, borderRadius: "50%", background: "var(--kb-orange-soft)", pointerEvents: "auto" }} />
        <button onClick={onOpenSettings} style={{ pointerEvents: "auto", background: "none", border: "none", color: "var(--kb-text)" }}>
          <Ic name="settings" size={20} />
        </button>
      </div>
    </div>
  );
}

Object.assign(window, { HomeScreen });
