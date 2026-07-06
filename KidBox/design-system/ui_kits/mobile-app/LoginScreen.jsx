// LoginScreen — recreates Features/Auth/LoginView.swift:
// logo + serif hero title/tagline, Google/Apple/Facebook provider pills,
// "o" divider, outlined email pill, legal footer with linked terms/privacy.
function LoginScreen({ onLogin }) {
  const [busy, setBusy] = React.useState(false);

  const go = () => {
    setBusy(true);
    setTimeout(() => { setBusy(false); onLogin(); }, 700);
  };

  const providerBtn = (label, icon) => (
    <button
      onClick={go}
      disabled={busy}
      style={{
        display: "flex", alignItems: "center", justifyContent: "center", gap: 10,
        height: 52, borderRadius: 999, border: "none",
        background: "var(--kb-btn-primary-bg)", color: "var(--kb-btn-primary-fg)",
        fontFamily: "var(--kb-font-sans)", fontSize: 16, fontWeight: 700,
        opacity: busy ? 0.6 : 1, cursor: busy ? "default" : "pointer",
      }}
    >
      {icon}{label}
    </button>
  );

  return (
    <div style={{
      position: "relative", height: "100%", overflowY: "auto",
      background: "var(--kb-bg)", fontFamily: "var(--kb-font-sans)",
      padding: "72px 28px 40px",
    }}>
      {/* Logo + serif hero */}
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 16, marginBottom: 52 }}>
        <img src="../../assets/kidbox-icon.png" alt="KidBox" style={{ width: 52, height: 52, borderRadius: 12 }} />
        <div style={{ fontFamily: "var(--kb-font-serif-display)", fontSize: 36, fontWeight: 600, color: "var(--kb-text)" }}>KidBox</div>
        <div style={{
          fontFamily: "var(--kb-font-serif-display)", fontSize: 26, fontWeight: 500,
          color: "var(--kb-text)", textAlign: "center", lineHeight: 1.3,
        }}>La tua famiglia,<br />in un'unica app.</div>
      </div>

      {/* Provider buttons */}
      <div style={{ display: "flex", flexDirection: "column", gap: 12, marginBottom: 20 }}>
        {providerBtn("Continua con Google", (
          <span style={{ width: 22, height: 22, borderRadius: "50%", background: "#fff", display: "inline-flex", alignItems: "center", justifyContent: "center", fontSize: 13, fontWeight: 800, color: "#4285F4" }}>G</span>
        ))}
        {providerBtn("Continua con Apple", <Ic name="apple" size={18} />)}
        {providerBtn("Continua con Facebook", (
          <span style={{ width: 22, height: 22, borderRadius: "50%", background: "#3B5998", display: "inline-flex", alignItems: "center", justifyContent: "center", fontSize: 14, fontWeight: 800, color: "#fff" }}>f</span>
        ))}
      </div>

      {/* Divider */}
      <div style={{ display: "flex", alignItems: "center", gap: 12, margin: "20px 0" }}>
        <div style={{ flex: 1, height: 1, background: "rgba(0,0,0,0.15)" }} />
        <div style={{ width: 24, height: 24, borderRadius: "50%", border: "1px solid rgba(0,0,0,0.2)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 11, color: "var(--kb-text-secondary)" }}>o</div>
        <div style={{ flex: 1, height: 1, background: "rgba(0,0,0,0.15)" }} />
      </div>

      {/* Email */}
      <button onClick={go} style={{
        display: "flex", alignItems: "center", justifyContent: "center", gap: 10, width: "100%",
        height: 52, borderRadius: 999, border: "1.5px solid rgba(0,0,0,0.25)", background: "transparent",
        fontFamily: "var(--kb-font-sans)", fontSize: 16, fontWeight: 700, color: "var(--kb-text)",
      }}>
        <Ic name="mail" size={16} />Continua con email
      </button>

      <p style={{
        marginTop: 32, textAlign: "center", fontSize: 12, color: "var(--kb-text-secondary)", lineHeight: 1.5,
      }}>
        Continuando, accetti i <u>Termini di Servizio</u> e la <u>Privacy Policy</u> di KidBox.
      </p>

      {busy && (
        <div style={{
          position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center",
          background: "rgba(0,0,0,0.05)", backdropFilter: "blur(1px)",
        }}>
          <div style={{
            display: "flex", flexDirection: "column", alignItems: "center", gap: 10,
            padding: 16, borderRadius: 14, background: "rgba(255,255,255,0.7)", backdropFilter: "blur(20px)",
          }}>
            <div style={{ width: 20, height: 20, border: "2.5px solid rgba(0,0,0,0.2)", borderTopColor: "var(--kb-text)", borderRadius: "50%", animation: "kbSpin 0.8s linear infinite" }} />
            <span style={{ fontSize: 14, fontWeight: 500 }}>Accesso in corso…</span>
          </div>
        </div>
      )}
      <style>{`@keyframes kbSpin{to{transform:rotate(360deg)}}`}</style>
    </div>
  );
}

Object.assign(window, { LoginScreen });
