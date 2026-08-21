import { useFamily } from "../FamilyContext";
import "./Home.css";

export default function Home() {
  const { currentFamily } = useFamily();

  return (
    <div>
      <h1>Home</h1>
      <div className="hero-card">
        <div className="hero-badge">{currentFamily?.memberCount ?? 0} membri</div>
        <div className="hero-title">{currentFamily?.name || "…"}</div>
      </div>
      <p className="hint">Scegli una sezione dalla barra laterale per iniziare.</p>
    </div>
  );
}
