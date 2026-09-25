import { NavLink } from "react-router-dom";
import { useState } from "react";
import { useAuth } from "../AuthContext";
import { useFamily } from "../FamilyContext";
import { NAV_SECTIONS, ACCOUNT_SECTIONS } from "../nav";
import { useTranslation } from "../i18n/LocaleContext";
import Modal from "./Modal";
import "./Sidebar.css";

export default function Sidebar() {
  const { logout } = useAuth();
  const { t } = useTranslation();
  const l = t.logoutConfirm;
  // Come iOS: uscire chiede conferma, un clic sbagliato nella barra non deve
  // riportare alla schermata di accesso.
  const [confirmLogout, setConfirmLogout] = useState(false);
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
      <div className="sidebar-top">
        <NavLink to="/" end className="sidebar-brand" title="KidBox">
          <img src="/icon.png" alt="" />
          {!collapsed && (
            <span className="wordmark">
              Kid<span className="wordmark-box">Box</span>
            </span>
          )}
        </NavLink>
        <button
          className="collapse-btn"
          onClick={toggleCollapsed}
          title={collapsed ? "Espandi barra laterale" : "Riduci a sole icone"}
        >
          ⬍
        </button>
      </div>

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
        <button className="nav-item logout-item" onClick={() => setConfirmLogout(true)} title={l.button}>
          <span className="nav-icon">🚪</span>
          {!collapsed && l.button}
        </button>
      </div>
      {confirmLogout && (
        <Modal onClose={() => setConfirmLogout(false)}>
          <div className="logout-confirm">
            <h3>{l.title}</h3>
            <p>{l.message}</p>
            <div className="logout-confirm-actions">
              <button className="btn-secondary" onClick={() => setConfirmLogout(false)} autoFocus>
                {l.cancel}
              </button>
              <button
                className="btn-danger"
                onClick={() => {
                  setConfirmLogout(false);
                  logout();
                }}
              >
                {l.confirm}
              </button>
            </div>
          </div>
        </Modal>
      )}
    </aside>
  );
}
