import { NavLink } from "react-router-dom";
import { useState } from "react";
import { useAuth } from "../AuthContext";
import { useFamily } from "../FamilyContext";
import { NAV_SECTIONS, ACCOUNT_SECTIONS } from "../nav";
import "./Sidebar.css";

export default function Sidebar() {
  const { logout } = useAuth();
  const { families, currentFamily, selectFamily } = useFamily();
  const [switcherOpen, setSwitcherOpen] = useState(false);
  const [collapsed, setCollapsed] = useState(
    () => localStorage.getItem("kidbox:sidebarCollapsed") === "1"
  );

  const toggleCollapsed = () => {
    setCollapsed((v) => {
      const next = !v;
      localStorage.setItem("kidbox:sidebarCollapsed", next ? "1" : "0");
      return next;
    });
    setSwitcherOpen(false);
  };

  return (
    <aside className={`sidebar${collapsed ? " collapsed" : ""}`}>
      <button
        className="collapse-btn"
        onClick={toggleCollapsed}
        title={collapsed ? "Espandi barra laterale" : "Riduci a sole icone"}
      >
        ⬍
      </button>

      <div className="family-switcher">
        <button
          className="family-switcher-btn"
          onClick={() => setSwitcherOpen((v) => !v)}
          title={currentFamily?.name || ""}
        >
          <span className="family-icon">🏠</span>
          {!collapsed && (
            <>
              <span className="family-text">
                <strong>{currentFamily?.name || "…"}</strong>
                <small>Cambia famiglia</small>
              </span>
              <span className="chevron">⌄</span>
            </>
          )}
        </button>
        {switcherOpen && families && families.length > 1 && (
          <ul className="family-list">
            {families.map((f) => (
              <li key={f.id}>
                <button
                  onClick={() => {
                    selectFamily(f.id);
                    setSwitcherOpen(false);
                  }}
                >
                  {f.name || f.id}
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      <nav className="nav-list">
        {NAV_SECTIONS.map((item) => (
          <NavLink
            key={item.key}
            to={item.path}
            end={item.exact}
            title={item.label}
            className={({ isActive }) => "nav-item" + (isActive ? " active" : "")}
          >
            <span className="nav-icon">{item.icon}</span>
            {!collapsed && item.label}
          </NavLink>
        ))}
      </nav>

      <div className="nav-divider" />

      <div className="nav-list account-list">
        {ACCOUNT_SECTIONS.map((item) => (
          <NavLink
            key={item.key}
            to={item.path}
            title={item.label}
            className={({ isActive }) => "nav-item" + (isActive ? " active" : "")}
          >
            <span className="nav-icon">{item.icon}</span>
            {!collapsed && item.label}
          </NavLink>
        ))}
        <button className="nav-item logout-item" onClick={logout} title="Esci">
          <span className="nav-icon">🚪</span>
          {!collapsed && "Esci"}
        </button>
      </div>
    </aside>
  );
}
