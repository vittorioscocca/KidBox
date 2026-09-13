/**
 * Wizard di benvenuto: porta sul web `OnboardingWalkthroughView` (iOS).
 *
 * Pagine, con la stessa numerazione del nativo:
 *   0-2  presentazione
 *   3    scelta percorso (crea / entra) — oppure, se si arriva da un link
 *        d'invito, la conferma con nome e cognome che fa subito il join
 *   4    nome e cognome
 *   5    crea famiglia (percorso «crea») o incolla il link (percorso «entra»)
 *   6    invita il partner (solo «crea»)
 *
 * Il nome si chiede prima della famiglia apposta: il documento membro nasce
 * alla creazione o al join, e averlo già permette di scriverlo lì subito invece
 * di lasciare il membro anonimo agli occhi degli altri.
 *
 * Una volta creata la famiglia (o fatto il join) non si torna indietro: la
 * scrittura su Firestore è avvenuta, e riproporre le pagine precedenti farebbe
 * pensare di poterla ancora annullare.
 */
import { useEffect, useRef, useState } from "react";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import Barcode from "../components/Barcode";
import * as analytics from "../services/analytics";
import { createInvite } from "../services/family";
import {
  JoinInviteError,
  createFamily,
  joinWithInvite,
  parseInvite,
  readInvitePreview,
} from "../services/onboarding";
import { loadProfile, saveNames } from "../services/profile";
import "./Onboarding.css";

const INFO_PAGES = [
  { icon: "❤️", tint: "#e8833a" },
  { icon: "🖼️", tint: "#8a6fd0" },
  { icon: "🩺", tint: "#3f9a6a" },
];

function stepName(page, path) {
  switch (page) {
    case 0:
    case 1:
    case 2:
      return `info_${page}`;
    case 3:
      return path === "linkJoin" ? "link_invite_confirm" : "path_picker";
    case 4:
      return "name";
    case 5:
      return path === "join" ? "join_family" : "create_family";
    default:
      return "invite";
  }
}

/**
 * @param {object} props
 * @param {object|null} props.pendingInvite invito arrivato dall'URL, già parsato
 * @param {boolean} props.hasFamily l'utente ha già una famiglia: si salta la
 *   presentazione e si va dritti alla conferma dell'invito
 * @param {string[]} props.memberOf id delle famiglie di cui è già membro
 * @param {(familyId: string|null) => void} props.onFinish
 */
export default function Onboarding({ pendingInvite, hasFamily, memberOf, onFinish }) {
  const { user } = useAuth();
  const { t } = useTranslation();
  const o = t.onboarding;

  const [path, setPath] = useState(pendingInvite ? "linkJoin" : null);
  const [page, setPage] = useState(pendingInvite && hasFamily ? 3 : 0);
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [createdFamilyId, setCreatedFamilyId] = useState(null);
  const [createdFamilyName, setCreatedFamilyName] = useState("");
  const [joinedFamilyId, setJoinedFamilyId] = useState(null);
  const [invitePreview, setInvitePreview] = useState(null);
  const startedAt = useRef(Date.now());
  const displayName = `${firstName.trim()} ${lastName.trim()}`.trim();

  // Nome già noto (login social, o profilo di un altro device): si precompila
  // e non si fa riscrivere.
  useEffect(() => {
    if (!user) return;
    loadProfile(user.uid).then((p) => {
      if (p.firstName || p.lastName) {
        setFirstName(p.firstName);
        setLastName(p.lastName);
      } else if (user.displayName) {
        const [fn, ...rest] = user.displayName.split(" ");
        setFirstName(fn || "");
        setLastName(rest.join(" "));
      }
    });
  }, [user]);

  useEffect(() => {
    if (!pendingInvite) return;
    readInvitePreview(pendingInvite).then(setInvitePreview);
  }, [pendingInvite]);

  useEffect(() => {
    analytics.onboardingStepShown(stepName(page, path), page + 1);
  }, [page, path]);

  const totalPages = path === "linkJoin" ? 4 : path === "join" ? 6 : 7;
  const committed = !!createdFamilyId || !!joinedFamilyId;
  const canGoBack = page > 0 && !busy && !committed && !(pendingInvite && hasFamily);

  const finish = (familyId) => {
    analytics.onboardingCompleted(Math.round((Date.now() - startedAt.current) / 1000));
    onFinish(familyId);
  };

  const advance = () => {
    analytics.onboardingStepCompleted(stepName(page, path));
    setError(null);
    setPage((p) => p + 1);
  };

  const saveNamesThenAdvance = async () => {
    if (!firstName.trim()) {
      setError(o.errNameRequired);
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await saveNames({ uid: user.uid, email: user.email, firstName, lastName });
      advance();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const joinErrorText = (err) => {
    if (!(err instanceof JoinInviteError)) return err.message;
    return {
      invalidPayload: o.errInvalid,
      invalidSecret: o.errInvalid,
      expired: o.errExpired,
      alreadyUsed: o.errUsed,
      alreadyMember: o.errAlreadyMember,
    }[err.code];
  };

  const join = async (invite) => {
    if (!firstName.trim()) {
      setError(o.errNameRequired);
      return;
    }
    setBusy(true);
    setError(null);
    analytics.familyJoinAttempted();
    try {
      const name = await saveNames({ uid: user.uid, email: user.email, firstName, lastName });
      const fid = await joinWithInvite({
        uid: user.uid,
        displayName: name,
        invite,
        alreadyMemberOf: memberOf,
      });
      analytics.familyJoined(true);
      setJoinedFamilyId(fid);
    } catch (err) {
      analytics.familyJoinFailed(err instanceof JoinInviteError ? err.code : "unknown");
      setError(joinErrorText(err));
    } finally {
      setBusy(false);
    }
  };

  // CTA in fondo alla card: cosa fa dipende dalla pagina.
  const handleCTA = () => {
    if (page < 3) return advance();
    if (page === 3 && path === "linkJoin") {
      return joinedFamilyId ? finish(joinedFamilyId) : join(pendingInvite);
    }
    if (page === 4) return saveNamesThenAdvance();
    if (page === 5 && path === "join") return finish(joinedFamilyId);
    if (page === 5 && path === "create") return advance();
    return finish(createdFamilyId);
  };

  const ctaLabel = () => {
    if (page === 3 && path === "linkJoin") {
      if (joinedFamilyId) return o.start;
      return busy ? o.joining : o.joinButton;
    }
    if (page === 4) return busy ? o.saving : o.next;
    if (page === 5 && path === "join") return o.start;
    if (page === 6) return o.inviteSent;
    return o.next;
  };

  // Il CTA non compare dove la card ha già il suo pulsante (scelta percorso,
  // creazione, join) finché quell'azione non è compiuta.
  const ctaVisible =
    page < 3 ||
    (page === 3 && path === "linkJoin") ||
    page === 4 ||
    (page === 5 && (path === "create" ? !!createdFamilyId : !!joinedFamilyId)) ||
    page === 6;
  const ctaDisabled =
    busy || (page === 3 && path === "linkJoin" && !joinedFamilyId && !firstName.trim());

  return (
    <div className="onb-screen">
      <div className="onb-top">
        {canGoBack ? (
          <button className="onb-back" onClick={() => setPage((p) => p - 1)}>
            ‹ {o.back}
          </button>
        ) : (
          <span />
        )}
        {page < 3 && !pendingInvite && (
          <button className="onb-skip" onClick={() => setPage(3)}>
            {o.skip}
          </button>
        )}
      </div>

      <section className="onb-card">
        {page < 3 && <InfoPage index={page} o={o} />}

        {page === 3 && path !== "linkJoin" && (
          <PathPicker
            o={o}
            onPick={(p) => {
              setPath(p);
              analytics.onboardingStepCompleted("path_picker");
              setPage(4);
            }}
          />
        )}

        {page === 3 && path === "linkJoin" && (
          <>
            <h2>
              {invitePreview?.familyName
                ? o.linkJoinTitleNamed.replace("%@", invitePreview.familyName)
                : o.linkJoinTitle}
            </h2>
            <p className="onb-lead">
              {invitePreview?.inviterName
                ? o.linkJoinHintNamed.replace("%@", invitePreview.inviterName)
                : o.linkJoinHint}
            </p>
            {joinedFamilyId ? (
              <p className="onb-success">✓ {o.joined}</p>
            ) : (
              <NameFields
                o={o}
                firstName={firstName}
                lastName={lastName}
                setFirstName={setFirstName}
                setLastName={setLastName}
                disabled={busy}
              />
            )}
          </>
        )}

        {page === 4 && (
          <>
            <h2>{o.nameTitle}</h2>
            <p className="onb-lead">{o.nameHint}</p>
            <NameFields
              o={o}
              firstName={firstName}
              lastName={lastName}
              setFirstName={setFirstName}
              setLastName={setLastName}
              disabled={busy}
              onSubmit={saveNamesThenAdvance}
            />
          </>
        )}

        {page === 5 && path === "create" && (
          <CreateFamilyCard
            o={o}
            uid={user?.uid}
            displayName={displayName}
            createdFamilyId={createdFamilyId}
            onCreated={(fid, name) => {
              setCreatedFamilyId(fid);
              setCreatedFamilyName(name);
            }}
          />
        )}

        {page === 5 && path === "join" && (
          <JoinFamilyCard o={o} busy={busy} joined={!!joinedFamilyId} onJoin={join} />
        )}

        {page === 6 && (
          <InviteCard
            o={o}
            uid={user?.uid}
            familyId={createdFamilyId}
            familyName={createdFamilyName}
            displayName={displayName}
          />
        )}

        {error && <p className="onb-error">{error}</p>}

        {ctaVisible && (
          <button className="onb-cta" disabled={ctaDisabled} onClick={handleCTA}>
            {ctaLabel()}
          </button>
        )}
        {page === 6 && (
          <button
            className="onb-link"
            onClick={() => {
              analytics.onboardingInviteStepSkipped();
              finish(createdFamilyId);
            }}
          >
            {o.inviteLater}
          </button>
        )}
      </section>

      <div className="onb-dots" aria-hidden="true">
        {Array.from({ length: totalPages }, (_, i) => (
          <span key={i} className={i === page ? "on" : ""} />
        ))}
      </div>
    </div>
  );
}

function InfoPage({ index, o }) {
  const { icon, tint } = INFO_PAGES[index];
  const title = o[`info${index}Title`];
  const body = o[`info${index}Body`];
  return (
    <div className="onb-info" key={index}>
      <div className="onb-info-icon" style={{ background: tint }}>
        {icon}
      </div>
      <h2 className="onb-info-title">
        {title.split("\n").map((line, i) => (
          <span key={i}>
            {line}
            {i === 0 && <br />}
          </span>
        ))}
      </h2>
      <p className="onb-lead">{body}</p>
    </div>
  );
}

function PathPicker({ o, onPick }) {
  return (
    <>
      <h2>{o.pathTitle}</h2>
      <div className="onb-paths">
        <button className="onb-path" onClick={() => onPick("create")}>
          <span className="onb-path-icon">🏠</span>
          <span>
            <strong>{o.pathCreate}</strong>
            <small>{o.pathCreateHint}</small>
          </span>
        </button>
        <button className="onb-path" onClick={() => onPick("join")}>
          <span className="onb-path-icon">🔗</span>
          <span>
            <strong>{o.pathJoin}</strong>
            <small>{o.pathJoinHint}</small>
          </span>
        </button>
      </div>
    </>
  );
}

function NameFields({ o, firstName, lastName, setFirstName, setLastName, disabled, onSubmit }) {
  return (
    <form
      className="onb-form"
      onSubmit={(e) => {
        e.preventDefault();
        onSubmit?.();
      }}
    >
      <label>
        {o.firstName}
        <input
          value={firstName}
          placeholder={o.firstNamePlaceholder}
          autoComplete="given-name"
          disabled={disabled}
          autoFocus
          onChange={(e) => setFirstName(e.target.value)}
        />
      </label>
      <label>
        {o.lastName}
        <input
          value={lastName}
          placeholder={o.lastNamePlaceholder}
          autoComplete="family-name"
          disabled={disabled}
          onChange={(e) => setLastName(e.target.value)}
        />
      </label>
      {/* Invio dentro il form = CTA, come ci si aspetta da una tastiera. */}
      <button type="submit" hidden />
    </form>
  );
}

function CreateFamilyCard({ o, uid, displayName, createdFamilyId, onCreated }) {
  const [familyName, setFamilyName] = useState("");
  const [childName, setChildName] = useState("");
  const [birthDate, setBirthDate] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const create = async (e) => {
    e.preventDefault();
    if (!familyName.trim() || busy) return;
    setBusy(true);
    setError(null);
    try {
      const fid = await createFamily({
        uid,
        displayName,
        name: familyName,
        childName,
        childBirthDate: birthDate ? new Date(`${birthDate}T12:00:00`) : null,
      });
      analytics.familyCreated();
      analytics.onboardingStepCompleted("create_family");
      onCreated(fid, familyName.trim());
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <h2>{o.createTitle}</h2>
      <p className="onb-lead">{o.createHint}</p>
      {createdFamilyId ? (
        <p className="onb-success">✓ {o.created}</p>
      ) : (
        <form className="onb-form" onSubmit={create}>
          <label>
            {o.familyName}
            <input
              value={familyName}
              placeholder={o.familyNamePlaceholder}
              disabled={busy}
              autoFocus
              required
              onChange={(e) => setFamilyName(e.target.value)}
            />
          </label>
          <label>
            {o.firstChild}
            <input
              value={childName}
              placeholder={o.childPlaceholder}
              disabled={busy}
              onChange={(e) => setChildName(e.target.value)}
            />
          </label>
          {childName.trim() && (
            <label>
              {o.birthDate}
              <input
                type="date"
                value={birthDate}
                max={new Date().toISOString().slice(0, 10)}
                disabled={busy}
                onChange={(e) => setBirthDate(e.target.value)}
              />
            </label>
          )}
          {error && <p className="onb-error">{error}</p>}
          <button className="onb-cta" type="submit" disabled={busy || !familyName.trim()}>
            {busy ? o.creating : o.createButton}
          </button>
        </form>
      )}
    </>
  );
}

function JoinFamilyCard({ o, busy, joined, onJoin }) {
  const [raw, setRaw] = useState("");
  const [invalid, setInvalid] = useState(false);
  const parsed = parseInvite(raw);

  const submit = (e) => {
    e.preventDefault();
    if (!parsed) {
      setInvalid(true);
      return;
    }
    setInvalid(false);
    onJoin(parsed);
  };

  return (
    <>
      <h2>{o.joinTitle}</h2>
      <p className="onb-lead">{o.joinHint}</p>
      {joined ? (
        <p className="onb-success">✓ {o.joined}</p>
      ) : (
        <form className="onb-form" onSubmit={submit}>
          <textarea
            value={raw}
            placeholder={o.joinPlaceholder}
            rows={3}
            disabled={busy}
            autoFocus
            spellCheck={false}
            onChange={(e) => {
              setRaw(e.target.value);
              setInvalid(false);
            }}
          />
          {invalid && <p className="onb-error">{o.errInvalid}</p>}
          <button className="onb-cta" type="submit" disabled={busy || !raw.trim()}>
            {busy ? o.joining : o.joinButton}
          </button>
        </form>
      )}
    </>
  );
}

function InviteCard({ o, uid, familyId, familyName, displayName }) {
  const [invite, setInvite] = useState(null);
  const [error, setError] = useState(null);
  const [copied, setCopied] = useState(false);
  const [showQr, setShowQr] = useState(false);

  const generate = async () => {
    setError(null);
    setInvite(null);
    try {
      setInvite(
        await createInvite({ familyId, familyName, inviterDisplayName: displayName, uid })
      );
      analytics.inviteGenerated();
    } catch (err) {
      setError(err.message);
    }
  };

  useEffect(() => {
    analytics.onboardingInviteStepShown();
    generate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [familyId]);

  const copy = async () => {
    await navigator.clipboard.writeText(invite.shareLink);
    analytics.inviteShared("copy_link");
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <>
      <h2>{o.inviteTitle}</h2>
      <p className="onb-lead">{o.inviteHint}</p>
      {error ? (
        <>
          <p className="onb-error">{error}</p>
          <button className="onb-secondary" onClick={generate}>
            {o.retry}
          </button>
        </>
      ) : !invite ? (
        <p className="onb-muted">{o.invitePreparing}</p>
      ) : (
        <>
          <input className="onb-linkbox" readOnly value={invite.shareLink} onFocus={(e) => e.target.select()} />
          <button className="onb-secondary" onClick={copy}>
            {copied ? `✓ ${o.copied}` : `📋 ${o.copyLink}`}
          </button>
          <p className="onb-muted">{o.inviteWarning}</p>
          <button className="onb-link" onClick={() => setShowQr((v) => !v)}>
            {showQr ? o.hideQr : o.showQr}
          </button>
          {showQr && (
            <div className="onb-qr">
              <Barcode text={invite.qrPayload} format="qr" />
              <small>{o.qrValid}</small>
              <small>{o.qrHint}</small>
            </div>
          )}
        </>
      )}
    </>
  );
}
