import { useEffect, useMemo, useState } from "react";
import Modal from "./Modal";
import { useTranslation } from "../i18n/LocaleContext";
import { evaluate, isWeak, LEVEL_COLOR } from "../passwordStrength";
import { pwnedCount, sha256Hex, UNKNOWN } from "../services/pwned";

/**
 * Rapporto di sicurezza: compromesse, duplicate, deboli — le stesse tre sezioni
 * di `PasswordsSecurityView` su iOS.
 *
 * Il controllo HIBP parte solo su richiesta, e l'esito viene scritto su
 * `pwnedCount` / `pwnedCheckedAt` come fa iOS, così il risultato è condiviso con
 * gli altri client invece di essere ricalcolato da ognuno.
 */
export default function PasswordSecurityModal({ entries, onScan, onClose }) {
  const { t } = useTranslation();
  const p = t.passwords;
  const [scanning, setScanning] = useState(false);
  const [clusters, setClusters] = useState([]);

  // I duplicati si calcolano confrontando gli hash: nessuna password in chiaro
  // esce da qui, e niente viene salvato.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const byHash = new Map();
      for (const e of entries) {
        if (!e.password) continue;
        // eslint-disable-next-line no-await-in-loop
        const h = await sha256Hex(e.password);
        byHash.set(h, [...(byHash.get(h) || []), e]);
      }
      if (cancelled) return;
      setClusters([...byHash.values()].filter((c) => c.length > 1));
    })();
    return () => {
      cancelled = true;
    };
  }, [entries]);

  const compromised = useMemo(
    () => entries.filter((e) => typeof e.pwnedCount === "number" && e.pwnedCount > 0),
    [entries]
  );

  const weakOnes = useMemo(
    () => entries.filter((e) => e.password && isWeak(evaluate(e.password).level)),
    [entries]
  );

  const scan = async () => {
    setScanning(true);
    for (const e of entries) {
      if (!e.password) continue;
      // eslint-disable-next-line no-await-in-loop
      const count = await pwnedCount(e.password);
      if (count === UNKNOWN) continue;
      // eslint-disable-next-line no-await-in-loop
      await onScan(e.id, count);
    }
    setScanning(false);
  };

  const row = (e, subtitle, tint) => (
    <li key={e.id}>
      <span className="pw-sec-dot" style={{ background: tint }} />
      <span className="pw-sec-main">
        <strong>{e.title}</strong>
        <span>{subtitle}</span>
      </span>
    </li>
  );

  return (
    <Modal onClose={onClose}>
      <div className="pw-security">
        <h2>{p.security}</h2>

        <h3>🔴 {p.compromised}</h3>
        {compromised.length === 0 ? (
          <p className="pw-hint">{p.noCompromised}</p>
        ) : (
          <ul className="pw-sec-list">
            {compromised.map((e) => row(e, p.pwnedFound(e.pwnedCount), "#d93838"))}
          </ul>
        )}

        <h3>🟡 {p.duplicates}</h3>
        {clusters.length === 0 ? (
          <p className="pw-hint">{p.noDuplicates}</p>
        ) : (
          <ul className="pw-sec-list">
            {clusters.map((cluster) => (
              <li key={cluster.map((e) => e.id).join("|")}>
                <span className="pw-sec-dot" style={{ background: "#c08c0d" }} />
                <span className="pw-sec-main">
                  <strong>{cluster.map((e) => e.title).join(", ")}</strong>
                  <span>{p.clusterOf(cluster.length)}</span>
                </span>
              </li>
            ))}
          </ul>
        )}

        <h3>🟠 {p.weakOnes}</h3>
        {weakOnes.length === 0 ? (
          <p className="pw-hint">{p.noWeak}</p>
        ) : (
          <ul className="pw-sec-list">
            {weakOnes.map((e) =>
              row(
                e,
                `${p.strength}: ${p[evaluate(e.password).level]}`,
                LEVEL_COLOR[evaluate(e.password).level]
              )
            )}
          </ul>
        )}

        <p className="pw-hint pw-privacy">{p.hibpPrivacy}</p>

        <div className="pw-form-actions">
          <button type="button" onClick={onClose}>
            {p.cancel}
          </button>
          <button type="button" className="pw-btn-primary" onClick={scan} disabled={scanning}>
            {scanning ? p.scanning : p.scanNow}
          </button>
        </div>
      </div>
    </Modal>
  );
}
