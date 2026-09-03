/**
 * Impostazioni famiglia. Porta sul web `FamilySettingsView` e la card Famiglia
 * di `SettingsView` (iOS): di che famiglia faccio parte, chi c'è dentro, come
 * invito qualcuno e come ne esco.
 *
 * Creare una famiglia da zero ed entrare con un codice restano nell'app: sono
 * il percorso di onboarding, e chi apre il sito una famiglia ce l'ha già.
 * Generare l'invito invece sta qui, perché è la cosa che si viene a cercare da
 * un computer — il link si incolla dove serve senza passare dal telefono.
 */
import { useEffect, useMemo, useState } from "react";
import { collection, onSnapshot } from "firebase/firestore";
import { useAuth } from "../AuthContext";
import { useFamily } from "../FamilyContext";
import { useChildren } from "../hooks/useChildren";
import { db } from "../firebase";
import { useTranslation } from "../i18n/LocaleContext";
import Barcode from "../components/Barcode";
import {
  createInvite,
  deleteFamily,
  leaveFamily,
  renameFamily,
  revokeInvite,
  revokeMember,
  transferOwnershipAndLeave,
} from "../services/family";
import "./Famiglia.css";

/**
 * I membri, letti senza filtro sul server e scremati qui.
 *
 * `useFamilyMembers` interroga `where("isDeleted", "==", false)`, che salta le
 * righe in cui quel campo non è mai stato scritto: qui una lista corta non è un
 * dettaglio estetico, decide se l'uscita passa dal trasferimento o dalla
 * cancellazione della famiglia. `loaded` distingue «nessun membro» da «non
 * ancora arrivati», così quella scelta non viene mostrata su dati incompleti.
 */
function useAllMembers(familyId) {
  const [state, setState] = useState({ members: [], loaded: false });

  useEffect(() => {
    if (!familyId) return undefined;
    setState({ members: [], loaded: false });
    return onSnapshot(collection(db, "families", familyId, "members"), (snap) =>
      setState({
        members: snap.docs.map((d) => ({ id: d.id, ...d.data() })),
        loaded: true,
      })
    );
  }, [familyId]);

  return state;
}

const memberLabel = (m) =>
  (m?.displayName || "").trim() || (m?.email || "").trim() || "Utente";

export default function Famiglia() {
  const { user } = useAuth();
  const { currentFamily, currentFamilyId } = useFamily();
  const { t } = useTranslation();
  const f = t.family;

  const { members, loaded: membersLoaded } = useAllMembers(currentFamilyId);
  const children = useChildren(currentFamilyId);

  const [name, setName] = useState(null);
  const [invite, setInvite] = useState(null);
  const [busy, setBusy] = useState(null);
  const [error, setError] = useState(null);
  const [notice, setNotice] = useState(null);
  const [transferring, setTransferring] = useState(false);

  const uid = user?.uid;

  /**
   * Dopo l'uscita si riparte dalla radice: i listener del resto del sito
   * punterebbero a dati non più leggibili, e la lista delle famiglie va
   * ricaricata da capo.
   */
  const leftFamily = () => {
    localStorage.removeItem("kidbox:currentFamilyId");
    window.location.assign("/");
  };

  // Un membro per utente, i cancellati fuori: è la stessa lista che decide se
  // puoi uscire o devi prima trasferire la ownership.
  const activeMembers = useMemo(() => {
    const seen = new Set();
    return members
      .filter((m) => !m.isDeleted && !seen.has(m.id) && seen.add(m.id))
      .sort((a, b) => memberLabel(a).localeCompare(memberLabel(b)));
  }, [members]);

  const ownerUid = currentFamily?.ownerUid || currentFamily?.createdBy || "";
  const isOwner =
    ownerUid === uid ||
    activeMembers.some((m) => m.id === uid && (m.role || "").toLowerCase() === "owner");

  const childrenSummary = children.length
    ? `${f.childrenLabel}: ${children.map((c) => c.name).filter(Boolean).join(", ")}`
    : f.noChildren;

  const editedName = name ?? currentFamily?.name ?? "";
  const nameDirty = editedName.trim() && editedName.trim() !== (currentFamily?.name || "");

  const run = async (label, action) => {
    setError(null);
    setBusy(label);
    try {
      await action();
    } catch (err) {
      setError(err.message === "ONLY_MEMBER" ? f.onlyMemberError : err.message);
    } finally {
      setBusy(null);
    }
  };

  const generateInvite = () =>
    run(f.generatingInvite, async () => {
      setInvite(
        await createInvite({
          familyId: currentFamilyId,
          familyName: currentFamily?.name || "",
          inviterDisplayName: user?.displayName || "",
          uid,
        })
      );
    });

  const dropInvite = () =>
    run(f.working, async () => {
      await revokeInvite({ familyId: currentFamilyId, inviteId: invite.inviteId });
      setInvite(null);
      setNotice(f.inviteRevoked);
    });

  const copyInvite = async () => {
    await navigator.clipboard.writeText(invite.shareLink);
    setNotice(f.linkCopied);
  };

  const leave = () => {
    // Uscire è irreversibile e da un browser è facile farlo per sbaglio: la
    // conferma dice cosa si perde prima, non dopo.
    if (!window.confirm(f.leaveConfirm)) return;
    run(f.working, async () => {
      await leaveFamily({ familyId: currentFamilyId, uid });
      leftFamily();
    });
  };

  const removeFamily = () => {
    if (!window.confirm(f.deleteConfirm)) return;
    run(f.working, async () => {
      await deleteFamily(currentFamilyId);
      leftFamily();
    });
  };

  const transferTo = (member) => {
    if (!window.confirm(f.transferConfirm.replace("%@", memberLabel(member)))) return;
    run(f.working, async () => {
      await transferOwnershipAndLeave({
        familyId: currentFamilyId,
        uid,
        newOwnerUid: member.id,
      });
      leftFamily();
    });
  };

  if (!currentFamilyId) {
    return (
      <div className="fam-page">
        <header className="pw-header">
          <h1>{f.title}</h1>
        </header>
        <section className="set-card">
          <h2>{f.noFamily}</h2>
          <p className="pw-hint">{f.noFamilyHint}</p>
        </section>
      </div>
    );
  }

  return (
    <div className="fam-page">
      <header className="pw-header">
        <h1>{f.title}</h1>
      </header>
      <p className="pw-hint">{f.intro}</p>

      {error && <p className="error">{error}</p>}
      {busy && <p className="docs-busy">{busy}</p>}
      {notice && (
        <p className="docs-notice">
          {notice}
          <button className="link-btn" onClick={() => setNotice(null)}>✕</button>
        </p>
      )}

      {/* ── Famiglia ─────────────────────────────────────────────────────── */}
      <section className="set-card fam-summary">
        {currentFamily?.heroPhotoURL ? (
          <img className="fam-photo" src={currentFamily.heroPhotoURL} alt="" />
        ) : (
          <div className="fam-photo fam-photo-empty">👪</div>
        )}
        <div className="fam-summary-body">
          <label>
            {f.name}
            <input value={editedName} onChange={(e) => setName(e.target.value)} />
          </label>
          <small>{childrenSummary}</small>
          <div className="pw-form-actions">
            <button
              className="pw-btn-primary"
              disabled={!nameDirty || busy}
              onClick={() =>
                run(f.working, async () => {
                  await renameFamily({ familyId: currentFamilyId, uid, name: editedName });
                  setName(null);
                  setNotice(f.nameSaved);
                })
              }
            >
              {f.save}
            </button>
          </div>
        </div>
      </section>

      {/* ── Membri ───────────────────────────────────────────────────────── */}
      <section className="set-card">
        <h2>{f.members}</h2>
        <p className="pw-hint">
          {activeMembers.length
            ? f.membersCount.replace("%d", activeMembers.length)
            : f.membersEmpty}
        </p>
        {activeMembers.map((m) => (
          <div className="fam-member" key={m.id}>
            <span className="fam-member-icon">{m.id === ownerUid ? "👑" : "👤"}</span>
            <span className="set-row-text">
              <strong>{memberLabel(m)}</strong>
              <small>{m.id === ownerUid ? f.owner : f.member}</small>
            </span>
            {isOwner && m.id !== uid && (
              <button
                className="link-btn danger"
                disabled={!!busy}
                onClick={() => {
                  if (!window.confirm(f.revokeConfirm.replace("%@", memberLabel(m)))) return;
                  run(f.working, () => revokeMember({ familyId: currentFamilyId, targetUid: m.id }));
                }}
              >
                {f.revoke}
              </button>
            )}
          </div>
        ))}
      </section>

      {/* ── Invito ───────────────────────────────────────────────────────── */}
      <section className="set-card">
        <h2>{f.invite}</h2>
        <p className="pw-hint">{f.inviteHint}</p>

        {!invite ? (
          <button className="prof-action" disabled={!!busy} onClick={generateInvite}>
            🔗 {f.generateInvite}
          </button>
        ) : (
          <>
            <div className="fam-qr">
              <Barcode text={invite.qrPayload} format="qr" />
            </div>
            <input className="fam-link" readOnly value={invite.shareLink} onFocus={(e) => e.target.select()} />
            <div className="fam-invite-actions">
              <button className="prof-action" onClick={copyInvite}>📋 {f.copyLink}</button>
              <button className="prof-action danger" disabled={!!busy} onClick={dropInvite}>
                {f.revokeInvite}
              </button>
            </div>
            <p className="pw-hint">{f.inviteExpiry}</p>
          </>
        )}
      </section>

      {/* ── Uscita ───────────────────────────────────────────────────────── */}
      <section className="set-card">
        <h2>{f.danger}</h2>
        <p className="pw-hint">{f.dangerHint}</p>

        {!membersLoaded ? null : activeMembers.length <= 1 ? (
          // Unico membro: uscire lascerebbe una famiglia orfana, quindi la sola
          // strada è eliminarla. Stessa regola del servizio su iOS.
          <>
            <p className="pw-hint">{f.onlyMemberError}</p>
            <button className="prof-action danger" disabled={!!busy} onClick={removeFamily}>
              🗑 {f.deleteFamily}
            </button>
          </>
        ) : (
          <>
            <button className="prof-action danger" disabled={!!busy} onClick={leave}>
              ⎋ {f.leave}
            </button>
            {isOwner && (
              <>
                <p className="pw-hint">{f.ownerLeaveHint}</p>
                {!transferring ? (
                  <button className="prof-action" disabled={!!busy} onClick={() => setTransferring(true)}>
                    👑 {f.transfer}
                  </button>
                ) : (
                  <div className="fam-transfer">
                    {activeMembers
                      .filter((m) => m.id !== uid)
                      .map((m) => (
                        <button key={m.id} className="set-option" disabled={!!busy} onClick={() => transferTo(m)}>
                          <strong>{memberLabel(m)}</strong>
                          <small>{m.email || m.id}</small>
                        </button>
                      ))}
                    <button className="link-btn" onClick={() => setTransferring(false)}>
                      {f.cancel}
                    </button>
                  </div>
                )}
                <button className="prof-action danger" disabled={!!busy} onClick={removeFamily}>
                  🗑 {f.deleteFamily}
                </button>
              </>
            )}
          </>
        )}
      </section>
    </div>
  );
}
