import { useEffect, useMemo, useRef, useState } from "react";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import {
  deleteGroup,
  deletePassword,
  deletePasswords,
  emojiForIcon,
  groupIdFor,
  listenPasswords,
  patchPassword,
  savePassword,
  saveGroup,
  seedDefaultGroups,
} from "../services/passwords";
import { MissingFamilyKeyError } from "../services/familyKey";
import { VISIBILITY_FAMILY, VISIBILITY_PRIVATE } from "../services/passwordCrypto";
import { evaluate, isWeak, LEVEL_COLOR } from "../passwordStrength";
import { parseOtpConfig, totp } from "../services/otp";
import { pwnedCount, UNKNOWN } from "../services/pwned";
import PasswordEditModal from "../components/PasswordEditModal";
import PasswordGroupsModal from "../components/PasswordGroupsModal";
import PasswordSecurityModal from "../components/PasswordSecurityModal";
import "./Password.css";

const SCOPES = ["all", "favorites", "family", "onlyMine"];

/* ── Import / export, stesso formato di `PasswordsTxtExporter` su iOS ────── */

const escapeTxt = (v) => (v || "").replace(/\\/g, "\\\\").replace(/\n/g, "\\n");
const unescapeTxt = (v) => (v || "").replace(/\\n/g, "\n").replace(/\\\\/g, "\\");

function buildTxt(entries, groupNameById) {
  const lines = ["# KidBox Password Export v1"];
  for (const e of entries) {
    lines.push("---");
    lines.push(`Title: ${escapeTxt(e.title)}`);
    lines.push(`Username: ${escapeTxt(e.username || "")}`);
    lines.push(`Password: ${escapeTxt(e.password)}`);
    lines.push(`WebSite: ${escapeTxt(e.website || "")}`);
    lines.push(`Group: ${escapeTxt(groupNameById.get(e.groupId) || "")}`);
    lines.push(`Visibility: ${e.visibility}`);
    lines.push(`Note: ${escapeTxt(e.notes || "")}`);
    lines.push(`CreatedBy: ${e.createdBy}`);
    lines.push(`Favorite: ${e.isFavorite ? "true" : "false"}`);
    lines.push("---");
  }
  return lines.join("\n");
}

function parseTxt(raw) {
  const blocks = [];
  let current = [];
  for (const line of raw.split(/\r?\n/)) {
    if (line.trim() === "---") {
      if (current.length) blocks.push(current);
      current = [];
      continue;
    }
    if (line.trim().startsWith("#")) continue;
    if (line.trim()) current.push(line);
  }
  if (current.length) blocks.push(current);

  return blocks
    .map((block) => {
      const map = {};
      for (const line of block) {
        const sep = line.indexOf(":");
        if (sep < 0) continue;
        map[line.slice(0, sep).trim()] = unescapeTxt(line.slice(sep + 1).trim());
      }
      return map;
    })
    .filter((m) => m.Title && m.Password);
}

/* ── Pagina ──────────────────────────────────────────────────────────────── */

export default function Password() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();
  const p = t.passwords;
  const members = useFamilyMembers(currentFamilyId);
  const fileInputRef = useRef(null);

  const [entries, setEntries] = useState([]);
  const [groups, setGroups] = useState([]);
  const [keyMissing, setKeyMissing] = useState(false);
  const [error, setError] = useState(null);

  const [search, setSearch] = useState("");
  const [scope, setScope] = useState("all");
  const [collapsed, setCollapsed] = useState(new Set());
  const [selecting, setSelecting] = useState(false);
  const [selected, setSelected] = useState(new Set());

  const [editing, setEditing] = useState(null);
  const [detailId, setDetailId] = useState(null);
  const [showGroups, setShowGroups] = useState(false);
  const [showSecurity, setShowSecurity] = useState(false);
  const [toast, setToast] = useState(null);

  useEffect(() => {
    if (!currentFamilyId || !user) return undefined;
    setKeyMissing(false);
    return listenPasswords({
      familyId: currentFamilyId,
      userId: user.uid,
      onChange: ({ entries: e, groups: g }) => {
        setEntries(e);
        setGroups(g.sort((a, b) => a.sortIndex - b.sortIndex || a.name.localeCompare(b.name)));
      },
      onError: (err) => {
        if (err instanceof MissingFamilyKeyError) setKeyMissing(true);
        else setError(err.message);
      },
    });
  }, [currentFamilyId, user]);

  // I gruppi di sistema si creano una volta sola per famiglia: l'id è
  // deterministico, quindi se li ha già fatti un altro client non si duplicano.
  useEffect(() => {
    if (!currentFamilyId || !user) return;
    seedDefaultGroups({ familyId: currentFamilyId, userId: user.uid, locale }).catch(() => {});
  }, [currentFamilyId, user, locale]);

  const showToast = (text) => {
    setToast(text);
    window.setTimeout(() => setToast(null), 1800);
  };

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return entries.filter((e) => {
      if (scope === "favorites" && !e.isFavorite) return false;
      if (scope === "family" && e.visibility !== VISIBILITY_FAMILY) return false;
      if (scope === "onlyMine" && !(e.visibility === VISIBILITY_PRIVATE && e.createdBy === user?.uid))
        return false;
      if (scope.startsWith("group:")) {
        const gid = scope.slice(6);
        const isUnassigned = gid === groupIdFor(currentFamilyId, "unassigned");
        if (isUnassigned ? e.groupId && e.groupId !== gid : e.groupId !== gid) return false;
      }
      if (!q) return true;
      return [e.title, e.username, e.website, e.notes]
        .filter(Boolean)
        .some((v) => v.toLowerCase().includes(q));
    });
  }, [entries, scope, search, user, currentFamilyId]);

  const sections = useMemo(() => {
    const byGroup = new Map();
    for (const e of filtered) {
      const key = groups.some((g) => g.id === e.groupId) ? e.groupId : "";
      byGroup.set(key, [...(byGroup.get(key) || []), e]);
    }
    const out = [];
    for (const g of groups) {
      const list = byGroup.get(g.id);
      if (list?.length) out.push({ id: g.id, title: g.name, icon: g.icon, color: g.color, entries: list });
    }
    const loose = byGroup.get("");
    if (loose?.length) {
      out.push({ id: "__none__", title: p.unassigned, icon: "tray", color: "#8E8E93", entries: loose });
    }
    return out.map((s) => ({
      ...s,
      entries: [...s.entries].sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0)),
    }));
  }, [filtered, groups, p]);

  // Un solo istante per tutta la lista: chiedere l'ora dentro ogni riga rende
  // il rendering impuro e le scadenze potrebbero cadere in momenti diversi.
  const now = Date.now();
  // Compatta/Esplodi guarda solo le sezioni che si vedono adesso: con un filtro
  // attivo il pulsante deve parlare di quelle, non di gruppi fuori schermo.
  const allCollapsed = sections.length > 0 && sections.every((s) => collapsed.has(s.id));

  const detail = entries.find((e) => e.id === detailId) || null;
  const groupNameById = useMemo(() => new Map(groups.map((g) => [g.id, g.name])), [groups]);

  const copy = async (value, label) => {
    await navigator.clipboard.writeText(value);
    showToast(`${label}: ${p.copied}`);
  };

  const toggleFavorite = (entry) =>
    patchPassword({
      familyId: currentFamilyId,
      userId: user.uid,
      id: entry.id,
      fields: { isFavorite: !entry.isFavorite },
    });

  const removeOne = async (id) => {
    if (!window.confirm(p.confirmDeleteOne)) return;
    await deletePassword({ familyId: currentFamilyId, userId: user.uid, id });
    setDetailId(null);
  };

  const removeSelected = async () => {
    if (!window.confirm(p.confirmDelete)) return;
    await deletePasswords({ familyId: currentFamilyId, userId: user.uid, ids: [...selected] });
    setSelected(new Set());
    setSelecting(false);
  };

  const exportTxt = () => {
    if (!window.confirm(p.exportWarning)) return;
    const blob = new Blob(["﻿" + buildTxt(entries, groupNameById)], {
      type: "text/plain;charset=utf-8",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    const stamp = new Date().toISOString().slice(0, 16).replace(/[:T]/g, "-");
    a.download = `KidBox-Passwords-${stamp}.txt`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const importTxt = async (file) => {
    const records = parseTxt(await file.text());
    // Le voci private di altri membri non sono importabili: la sotto-chiave è
    // legata al creatore, e riscriverle a nome mio ne cambierebbe il senso.
    const mine = records.filter(
      (r) =>
        (r.Visibility || VISIBILITY_PRIVATE) !== VISIBILITY_PRIVATE ||
        !r.CreatedBy ||
        r.CreatedBy === user.uid
    );
    if (mine.length === 0) {
      showToast(p.importNothing);
      return;
    }
    for (const r of mine) {
      const group = groups.find((g) => g.name === r.Group);
      // eslint-disable-next-line no-await-in-loop
      await savePassword({
        familyId: currentFamilyId,
        userId: user.uid,
        entry: {
          title: r.Title,
          username: r.Username || null,
          password: r.Password,
          website: r.WebSite || null,
          notes: r.Note || null,
          groupId: group?.id || null,
          visibility: r.Visibility || VISIBILITY_PRIVATE,
          isFavorite: ["true", "1", "yes", "si"].includes((r.Favorite || "").toLowerCase()),
        },
      });
    }
    showToast(p.importDone(mine.length));
  };

  const emptyMessage = () => {
    if (search.trim()) return p.emptySearch;
    if (scope === "favorites") return p.emptyFavorites;
    if (scope === "family") return p.emptyFamily;
    if (scope === "onlyMine") return p.emptyOnlyMine;
    return p.emptyAll;
  };

  if (keyMissing) {
    return (
      <div className="pw-page">
        <h1>{p.title}</h1>
        <p className="pw-locked">🔒 {p.keyMissing}</p>
      </div>
    );
  }

  return (
    <div className="pw-page">
      <header className="pw-header">
        <h1>{p.title}</h1>
        <div className="pw-toolbar">
          <input
            className="pw-search"
            type="search"
            placeholder={p.search}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <button
            onClick={() =>
              setCollapsed(allCollapsed ? new Set() : new Set(sections.map((s) => s.id)))
            }
            disabled={sections.length === 0}
          >
            {allCollapsed ? `▸ ${p.expandAll}` : `▾ ${p.collapseAll}`}
          </button>
          <button onClick={() => setShowSecurity(true)}>🛡 {p.security}</button>
          <button onClick={() => setShowGroups(true)}>📁 {p.manageGroups}</button>
          <button onClick={exportTxt}>⬇ {p.exportTxt}</button>
          <button onClick={() => fileInputRef.current?.click()}>⬆ {p.importTxt}</button>
          <button
            onClick={() => {
              setSelecting((v) => !v);
              setSelected(new Set());
            }}
          >
            {selecting ? p.cancel : p.select}
          </button>
          {selecting && selected.size > 0 && (
            <button className="pw-danger" onClick={removeSelected}>
              {p.deleteCount(selected.size)}
            </button>
          )}
          <button className="pw-btn-primary" onClick={() => setEditing({})}>
            + {p.add}
          </button>
        </div>
      </header>

      <input
        ref={fileInputRef}
        type="file"
        accept=".txt,text/plain"
        hidden
        onChange={(e) => {
          const f = e.target.files?.[0];
          e.target.value = "";
          if (f) importTxt(f);
        }}
      />

      <div className="pw-chips">
        {SCOPES.map((s) => (
          <button
            key={s}
            className={"pw-chip" + (scope === s ? " selected" : "")}
            onClick={() => setScope(s)}
          >
            {p[`scope${s.charAt(0).toUpperCase()}${s.slice(1)}`]}
          </button>
        ))}
        {groups.map((g) => (
          <button
            key={g.id}
            className={"pw-chip" + (scope === `group:${g.id}` ? " selected" : "")}
            onClick={() => setScope(`group:${g.id}`)}
          >
            {emojiForIcon(g.icon)} {g.name}
          </button>
        ))}
      </div>

      {error && <p className="error">{error}</p>}

      {sections.length === 0 ? (
        <p className="pw-empty">{emptyMessage()}</p>
      ) : (
        sections.map((section) => {
          const open = !collapsed.has(section.id);
          return (
            <section key={section.id} className="pw-section">
              <button
                className="pw-section-head"
                onClick={() =>
                  setCollapsed((c) => {
                    const next = new Set(c);
                    if (next.has(section.id)) next.delete(section.id);
                    else next.add(section.id);
                    return next;
                  })
                }
              >
                <span className="pw-group-dot" style={{ background: section.color }} />
                <span>{emojiForIcon(section.icon)}</span>
                <span className="pw-section-title">{section.title}</span>
                <span className="pw-section-count">{section.entries.length}</span>
                <span className="pw-section-chevron">{open ? "▾" : "▸"}</span>
              </button>

              {open && (
                <ul className="pw-list">
                  {section.entries.map((e) => (
                    <PasswordRow
                      key={e.id}
                      entry={e}
                      p={p}
                      selecting={selecting}
                      selected={selected.has(e.id)}
                      onToggleSelect={() =>
                        setSelected((s) => {
                          const next = new Set(s);
                          if (next.has(e.id)) next.delete(e.id);
                          else next.add(e.id);
                          return next;
                        })
                      }
                      now={now}
                      onOpen={() => setDetailId(e.id)}
                      onToggleFavorite={() => toggleFavorite(e)}
                    />
                  ))}
                </ul>
              )}
            </section>
          );
        })
      )}

      {detail && (
        <PasswordDetail
          entry={detail}
          groupName={groupNameById.get(detail.groupId)}
          p={p}
          locale={locale}
          onCopy={copy}
          onClose={() => setDetailId(null)}
          onEdit={() => {
            setEditing(detail);
            setDetailId(null);
          }}
          onDelete={() => removeOne(detail.id)}
          onToggleFavorite={() => toggleFavorite(detail)}
          onCheckPwned={async () => {
            const count = await pwnedCount(detail.password);
            if (count === UNKNOWN) {
              showToast(p.pwnedUnknown);
              return;
            }
            await patchPassword({
              familyId: currentFamilyId,
              userId: user.uid,
              id: detail.id,
              fields: { pwnedCount: count, pwnedCheckedAt: new Date() },
            });
          }}
          duplicateCount={
            entries.filter((o) => o.id !== detail.id && o.password === detail.password).length
          }
        />
      )}

      {editing && (
        <PasswordEditModal
          entry={editing}
          groups={groups}
          members={members}
          currentUid={user?.uid}
          onSave={(entry) => savePassword({ familyId: currentFamilyId, userId: user.uid, entry })}
          onClose={() => setEditing(null)}
        />
      )}

      {showGroups && (
        <PasswordGroupsModal
          groups={groups}
          onSave={(group) => saveGroup({ familyId: currentFamilyId, userId: user.uid, group })}
          onDelete={(id) => deleteGroup({ familyId: currentFamilyId, userId: user.uid, id })}
          onClose={() => setShowGroups(false)}
        />
      )}

      {showSecurity && (
        <PasswordSecurityModal
          entries={entries}
          onScan={(id, count) =>
            patchPassword({
              familyId: currentFamilyId,
              userId: user.uid,
              id,
              fields: { pwnedCount: count, pwnedCheckedAt: new Date() },
            })
          }
          onClose={() => setShowSecurity(false)}
        />
      )}

      {toast && <div className="pw-toast">{toast}</div>}
    </div>
  );
}

/* ── Riga ────────────────────────────────────────────────────────────────── */

function PasswordRow({ entry, p, now, selecting, selected, onToggleSelect, onOpen, onToggleFavorite }) {
  const strength = evaluate(entry.password);
  const expired = entry.expiresAt && entry.expiresAt < now;
  return (
    <li className="pw-row">
      {selecting && <input type="checkbox" checked={selected} onChange={onToggleSelect} />}
      <button className="pw-row-main" onClick={onOpen}>
        <span className="pw-row-title">{entry.title}</span>
        {entry.username && <span className="pw-row-user">{entry.username}</span>}
        <span className="pw-row-badges">
          {expired && <span className="pw-badge pw-badge-red">{p.expired}</span>}
          {entry.pwnedCount > 0 && <span className="pw-badge pw-badge-red">{p.compromised}</span>}
          {isWeak(strength.level) && (
            <span className="pw-badge" style={{ background: LEVEL_COLOR[strength.level] }}>
              {p[strength.level]}
            </span>
          )}
        </span>
      </button>
      <button
        className={"pw-star" + (entry.isFavorite ? " on" : "")}
        onClick={onToggleFavorite}
        title={p.favorite}
      >
        {entry.isFavorite ? "★" : "☆"}
      </button>
    </li>
  );
}

/* ── Dettaglio ───────────────────────────────────────────────────────────── */

function PasswordDetail({
  entry,
  groupName,
  p,
  locale,
  onCopy,
  onClose,
  onEdit,
  onDelete,
  onToggleFavorite,
  onCheckPwned,
  duplicateCount,
}) {
  const [revealed, setRevealed] = useState(false);
  const [code, setCode] = useState(null);
  const strength = evaluate(entry.password);
  const otpConfig = useMemo(() => parseOtpConfig(entry.otp), [entry.otp]);

  // Il codice a due fattori si rigenera da solo: senza tick resterebbe fermo su
  // quello calcolato all'apertura, e dopo trenta secondi sarebbe sbagliato.
  useEffect(() => {
    if (!otpConfig) return undefined;
    let alive = true;
    const tick = async () => {
      const next = await totp(otpConfig);
      if (alive) setCode(next);
    };
    tick();
    const id = window.setInterval(tick, 1000);
    return () => {
      alive = false;
      window.clearInterval(id);
    };
  }, [otpConfig]);

  const fmt = (millis) =>
    millis
      ? new Date(millis).toLocaleDateString(locale === "en" ? "en-US" : "it-IT", {
          day: "2-digit",
          month: "long",
          year: "numeric",
        })
      : "—";

  const row = (label, value, copyValue) =>
    value ? (
      <div className="pw-detail-row">
        <span className="pw-detail-label">{label}</span>
        <span className="pw-detail-value">{value}</span>
        {copyValue && <button onClick={() => onCopy(copyValue, label)}>{p.copy}</button>}
      </div>
    ) : null;

  return (
    <div className="pw-detail-overlay" onClick={onClose}>
      <aside className="pw-detail" onClick={(e) => e.stopPropagation()}>
        <header>
          <h2>{entry.title}</h2>
          <button className={"pw-star" + (entry.isFavorite ? " on" : "")} onClick={onToggleFavorite}>
            {entry.isFavorite ? "★" : "☆"}
          </button>
          <button onClick={onClose}>✕</button>
        </header>

        {row(p.fieldUsername, entry.username, entry.username)}

        <div className="pw-detail-row">
          <span className="pw-detail-label">{p.fieldPassword}</span>
          <span className="pw-detail-value pw-mono">
            {revealed ? entry.password : "••••••••••••"}
          </span>
          <button onClick={() => setRevealed((v) => !v)}>{revealed ? p.hide : p.show}</button>
          <button onClick={() => onCopy(entry.password, p.fieldPassword)}>{p.copy}</button>
        </div>

        <div className="pw-strength">
          <div className="pw-strength-track">
            <span
              style={{
                width: `${Math.max(4, strength.fillFraction * 100)}%`,
                background: LEVEL_COLOR[strength.level],
              }}
            />
          </div>
          <div className="pw-strength-labels">
            <span style={{ color: LEVEL_COLOR[strength.level] }}>{p[strength.level]}</span>
            <span>{p.bits(Math.round(strength.estimatedBits))}</span>
          </div>
        </div>

        {entry.website && (
          <div className="pw-detail-row">
            <span className="pw-detail-label">{p.fieldWebsite}</span>
            <span className="pw-detail-value">{entry.website}</span>
            <a
              href={entry.website.startsWith("http") ? entry.website : `https://${entry.website}`}
              target="_blank"
              rel="noreferrer"
            >
              {p.open}
            </a>
            <button onClick={() => onCopy(entry.website, p.fieldWebsite)}>{p.copy}</button>
          </div>
        )}

        {code && (
          <div className="pw-detail-row">
            <span className="pw-detail-label">{p.fieldOtp}</span>
            <span className="pw-detail-value pw-mono pw-otp">{code.code}</span>
            <span className="pw-otp-left">{code.secondsLeft}s</span>
            <button onClick={() => onCopy(code.code, p.fieldOtp)}>{p.copy}</button>
          </div>
        )}

        {row(p.fieldGroup, groupName)}
        {row(p.fieldNotes, entry.notes)}
        {row(p.passwordUpdatedAt, fmt(entry.passwordUpdatedAt))}
        {entry.expiresAt ? row(p.fieldExpires, p.expiresOn(fmt(entry.expiresAt))) : null}

        <div className="pw-detail-row">
          <span className="pw-detail-label">HIBP</span>
          <span className="pw-detail-value">
            {typeof entry.pwnedCount !== "number"
              ? "—"
              : entry.pwnedCount > 0
                ? p.pwnedFound(entry.pwnedCount)
                : p.pwnedSafe}
          </span>
          <button onClick={onCheckPwned}>{p.scanNow}</button>
        </div>

        {duplicateCount > 0 && <p className="pw-warn">🟡 {p.duplicateOf(duplicateCount)}</p>}

        <div className="pw-form-actions">
          <button className="pw-danger" onClick={onDelete}>
            {p.delete}
          </button>
          <button className="pw-btn-primary" onClick={onEdit}>
            {p.edit}
          </button>
        </div>
      </aside>
    </div>
  );
}
