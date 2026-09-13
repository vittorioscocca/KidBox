/**
 * Mattoni delle pagine Impostazioni: gruppi con etichetta, righe con icona
 * tinta, interruttori, selettori a segmenti, intestazione con freccia indietro.
 * Sono gli stessi in indice e pagine di dettaglio, così ogni voce si apre e
 * si legge allo stesso modo.
 */
import { Link } from "react-router-dom";
import "../pages/Impostazioni.css";

/** Etichetta di gruppo + card che raccoglie le righe. */
export function Group({ label, children, tone }) {
  return (
    <section className="set-group">
      {label && <h2 className={`set-group-label${tone ? ` ${tone}` : ""}`}>{label}</h2>}
      <div className="set-card set-list">{children}</div>
    </section>
  );
}

/** Intestazione di pagina: freccia indietro (se `back`) e titolo. */
export function PageHeader({ title, back, backLabel }) {
  return (
    <header className="set-header">
      {back && (
        <Link className="set-back" to={back} title={backLabel} aria-label={backLabel}>
          ←
        </Link>
      )}
      <h1>{title}</h1>
    </header>
  );
}

/**
 * Una riga: icona in un riquadro tinto, titolo con eventuale sottotitolo, e a
 * destra un valore, un interruttore, un selettore o una freccia. `to` la rende
 * un link, `onClick` un pulsante, altrimenti è statica.
 */
export function Row({ icon, tint = "orange", title, hint, right, chevron, to, href, onClick, danger, disabled, children }) {
  const body = (
    <>
      <span className={`set-icon ${tint}`}>{icon}</span>
      <span className="set-row-text">
        <strong>{title}</strong>
        {hint && <small>{hint}</small>}
      </span>
      {right !== undefined && <span className="set-row-right">{right}</span>}
      {chevron && <span className="set-chevron">›</span>}
    </>
  );
  const cls = `set-row${danger ? " danger" : ""}${disabled ? " disabled" : ""}`;
  if (to) return <Link className={cls} to={to}>{body}</Link>;
  if (href) {
    return (
      <a className={cls} href={href} target={href.startsWith("http") ? "_blank" : undefined} rel="noreferrer">
        {body}
      </a>
    );
  }
  if (onClick) {
    return (
      <button className={cls} onClick={onClick} disabled={disabled}>
        {body}
      </button>
    );
  }
  return (
    <div className={cls}>
      {body}
      {children}
    </div>
  );
}

/** Riga che si apre in verticale: icona in alto, contenuto libero sotto il titolo. */
export function StackRow({ icon, tint = "orange", title, hint, children }) {
  return (
    <div className="set-row set-stack">
      <span className={`set-icon ${tint}`}>{icon}</span>
      <span className="set-row-text">
        {title && <strong>{title}</strong>}
        {hint && <small>{hint}</small>}
        {children}
      </span>
    </div>
  );
}

export function Switch({ checked, disabled, onChange }) {
  return (
    <input
      type="checkbox"
      className="set-switch"
      checked={checked}
      disabled={disabled}
      onChange={(e) => onChange(e.target.checked)}
    />
  );
}

/** Interruttore con la sua riga: l'intera riga è cliccabile. */
export function SwitchRow({ icon, tint = "orange", title, hint, checked, disabled, onChange }) {
  return (
    <label className={`set-row${disabled ? " disabled" : ""}`}>
      <span className={`set-icon ${tint}`}>{icon}</span>
      <span className="set-row-text">
        <strong>{title}</strong>
        {hint && <small>{hint}</small>}
      </span>
      <span className="set-row-right">
        <Switch checked={checked} disabled={disabled} onChange={onChange} />
      </span>
    </label>
  );
}

/** Selettore a segmenti (tema, lingua). */
export function Segmented({ options, value, onChange }) {
  return (
    <span className="set-seg">
      {options.map((opt) => (
        <button
          key={opt.value}
          className={value === opt.value ? "on" : ""}
          onClick={() => onChange(opt.value)}
          title={opt.title}
        >
          {opt.label}
        </button>
      ))}
    </span>
  );
}

/** Riga «si imposta dal telefono»: non è un comando spento, è un'informazione. */
export function DeviceRow({ icon, tint = "grey", title, hint, label }) {
  return <Row icon={icon} tint={tint} title={title} hint={hint} right={<em className="set-device">{label}</em>} />;
}

export function Value({ children }) {
  return <span className="set-value">{children}</span>;
}
