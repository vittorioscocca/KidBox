import { useEffect, useMemo, useRef, useState } from "react";
import Modal from "./Modal";
import { useTranslation } from "../i18n/LocaleContext";
import { adoptHandedFamilyKey, syncFamilyKeysV2 } from "../services/familyKey";
import { openHandoffRoom } from "../services/keyHandoff";
import QrCanvas from "./QrCanvas";
import {
  PasskeyUnsupportedError,
  VaultExistsError,
  WrongSecretError,
  addPasskeySlot,
  adoptHandedRk,
  createVault,
  generateRecoveryCode,
  listVaultSlots,
  normalizeRecoveryCode,
  openVaultWithPasskey,
  openVaultWithRecoveryCode,
  passkeyMaybeSupported,
  replaceRecoveryCode,
} from "../services/familyKeyVault";
import "./KeyVaultPrompt.css";

/**
 * «Proteggi la chiave della tua famiglia» (piano v2, sezioni 4 bis, 4 ter, 7).
 *
 * Se la cassaforte dell'utente non esiste la crea (codice di recupero sempre,
 * passkey in aggiunta); se esiste la apre (passkey o codice). Il codice creato
 * su un'app è lo stesso che si scrive qui: una cassaforte per utente.
 *
 * Dopo: copia v2 verificata per ogni famiglia di `familyIds`. La v1 non si
 * tocca. `allowLater` = c'è «Più tardi» (spento solo con `enforce`).
 *
 * Da Impostazioni › Sicurezza: `mode` "regenerate" (codice nuovo, stessa RK) o
 * "addPasskey". La RK in IndexedDB non è esportabile, quindi in entrambi i casi
 * si riapre prima la cassaforte (passkey o codice) per avere i byte.
 */
export default function KeyVaultPrompt({ user, familyIds, allowLater = true, onDone, onLater, mode = "default" }) {
  const { t } = useTranslation();
  const k = t.keyVault;
  const [step, setStep] = useState("loading");
  const [slots, setSlots] = useState([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [notice, setNotice] = useState(null);
  const [typedCode, setTypedCode] = useState("");
  const [copied, setCopied] = useState(false);
  const [canPasskey, setCanPasskey] = useState(false);
  const rk = useRef(null); // { rkBytes, rkId } solo finché serve aggiungere una passkey
  const room = useRef(null); // stanza del QR aperta (close)
  const [qr, setQr] = useState(null); // { text, expired }
  const code = useMemo(() => generateRecoveryCode(), []);
  const positions = useMemo(() => {
    const all = Array.from({ length: 24 }, (_, i) => i);
    for (let i = all.length - 1; i > 0; i -= 1) {
      const j = crypto.getRandomValues(new Uint32Array(1))[0] % (i + 1);
      [all[i], all[j]] = [all[j], all[i]];
    }
    return all.slice(0, 4).sort((a, b) => a - b);
  }, []);
  const [confirmChars, setConfirmChars] = useState(["", "", "", ""]);
  const canonical = normalizeRecoveryCode(code);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setCanPasskey(await passkeyMaybeSupported());
      try {
        const s = await listVaultSlots(user.uid);
        if (cancelled) return;
        setSlots(s);
        if (mode === "receive") {
          startPhone();
          return;
        }
        setStep(s.length > 0 ? "open" : mode === "default" ? "intro" : "open");
      } catch {
        if (!cancelled) {
          setError(k.error);
          setStep("intro");
        }
      }
    })();
    return () => {
      cancelled = true;
      wipe();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user.uid]);

  function closeRoom() {
    room.current?.close();
    room.current = null;
  }

  const startPhone = () =>
    run(async () => {
      closeRoom();
      setQr(null);
      setStep("phone");
      const r = await openHandoffRoom({
        uid: user.uid,
        label: browserLabel(),
        onPayload: (p) =>
          run(async () => {
            room.current = null;
            if (p.kind === "rk") {
              const result = await adoptHandedRk(user.uid, p.bytes);
              await afterUnlock(result, { offerPasskey: true });
            } else if (p.kind === "familyKey" && p.familyId) {
              await adoptHandedFamilyKey({ familyId: p.familyId, userId: user.uid, rawKey: p.bytes });
              p.bytes.fill(0);
              setNotice(k.phoneGotFamily);
              setStep("done");
            }
          }),
        onError: () => {
          room.current = null;
          setError(k.phoneFailed);
          setQr((q) => (q ? { ...q, expired: true } : q));
        },
      });
      room.current = r;
      setQr({ text: r.qrText, expired: false });
      setTimeout(() => setQr((q) => (q && q.text === r.qrText ? { ...q, expired: true } : q)), r.expiresAt - Date.now());
    });

  function wipe() {
    closeRoom();
    if (rk.current?.rkBytes) rk.current.rkBytes.fill(0);
    rk.current = null;
  }

  const finish = () => {
    wipe();
    onDone?.();
  };

  const later = () => {
    wipe();
    onLater?.();
  };

  const afterUnlock = async (result, { offerPasskey }) => {
    rk.current = result;
    await syncFamilyKeysV2({ userId: user.uid, familyIds: familyIds || [] });
    if (mode === "regenerate") setStep("code");
    else if (mode === "addPasskey") setStep("passkey");
    else if (offerPasskey && canPasskey) setStep("passkey");
    else setStep("done");
  };

  const run = async (fn) => {
    setBusy(true);
    setError(null);
    try {
      await fn();
    } catch (err) {
      if (err instanceof WrongSecretError) setError(k.wrongCode);
      else if (err instanceof PasskeyUnsupportedError) setError(k.passkeyNotUsable);
      else if (err?.name === "NotAllowedError") setError(null); // annullata dall'utente
      else {
        console.warn("[Vault]", err);
        setError(k.error);
      }
    } finally {
      setBusy(false);
    }
  };

  const confirmCreate = () =>
    run(async () => {
      const norm = (c) => (c || "").toUpperCase().replace(/O/g, "0").replace(/[IL]/g, "1");
      const ok = positions.every((p, i) => canonical?.[p] === norm(confirmChars[i]));
      if (!ok) {
        setError(k.confirmWrong);
        return;
      }
      if (mode === "regenerate") {
        await replaceRecoveryCode({ uid: user.uid, rkBytes: rk.current.rkBytes, rkId: rk.current.rkId, recoveryCode: code });
        setNotice(k.regenerated);
        setStep("done");
        return;
      }
      try {
        const result = await createVault({ uid: user.uid, recoveryCode: code });
        await afterUnlock(result, { offerPasskey: true });
      } catch (err) {
        if (!(err instanceof VaultExistsError)) throw err;
        // Creata un attimo fa da un altro dispositivo: si apre quella.
        setSlots(await listVaultSlots(user.uid));
        setNotice(k.existsNow);
        setStep("open");
      }
    });

  const openWithCode = () =>
    run(async () => {
      const result = await openVaultWithRecoveryCode({ uid: user.uid, recoveryCode: typedCode });
      await afterUnlock(result, { offerPasskey: true });
    });

  const openWithPasskey = () =>
    run(async () => {
      const result = await openVaultWithPasskey({ uid: user.uid, slots });
      await afterUnlock(result, { offerPasskey: false });
    });

  const createPasskey = () =>
    run(async () => {
      try {
        await addPasskeySlot({
          uid: user.uid,
          email: user.email,
          displayName: user.displayName,
          rkBytes: rk.current.rkBytes,
          rkId: rk.current.rkId,
          label: browserLabel(),
        });
        setNotice(k.passkeyAdded);
        setStep("done");
      } catch (err) {
        if (err instanceof PasskeyUnsupportedError) {
          setNotice(k.passkeyUnsupported);
          setStep("done");
          return;
        }
        if (err?.name === "NotAllowedError") return;
        throw err;
      }
    });

  const copyCode = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      /* il codice resta a schermo */
    }
  };

  const fileText = () => `${k.fileHeader}\n\n${code}\n\n${user.email || ""}\n\n${k.codeWarning}\n${k.codeWhere}\n`;

  const downloadCode = () => {
    const url = URL.createObjectURL(new Blob([fileText()], { type: "text/plain" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = "kidbox-codice-di-recupero.txt";
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };

  const printCode = () => {
    const w = window.open("", "_blank", "width=600,height=500");
    if (!w) return;
    const pre = w.document.createElement("pre");
    pre.style.cssText = "font: 16px/1.5 ui-monospace, monospace; white-space: pre-wrap; padding: 24px";
    pre.textContent = fileText();
    w.document.body.appendChild(pre);
    w.print();
  };

  const laterButton = allowLater && step !== "done" && !(mode === "receive" && step === "phone") && (
    <button type="button" className="kv-link" onClick={later} disabled={busy}>
      {mode === "default" ? k.later : k.cancel}
    </button>
  );

  return (
    <Modal onClose={() => {}}>
      <div className="kv">
        {step === "loading" && <p className="kv-lead">…</p>}

        {step === "intro" && (
          <>
            <div className="kv-icon" aria-hidden="true">🔐</div>
            <h2 className="modal-title">{k.protectTitle}</h2>
            <p className="kv-lead">{k.protectBody}</p>
            <p className="kv-small">{k.whenNeeded}</p>
            <button type="button" className="kv-primary" onClick={() => setStep("code")}>
              {k.createCta}
            </button>
            {laterButton}
          </>
        )}

        {step === "code" && (
          <>
            <h2 className="modal-title">{k.codeTitle}</h2>
            <p className="kv-lead">{k.codeLead}</p>
            <div className="kv-code" data-testid="kv-code">{code}</div>
            <div className="kv-actions">
              <button type="button" className="kv-secondary" onClick={copyCode}>
                {copied ? k.copied : k.copy}
              </button>
              <button type="button" className="kv-secondary" onClick={downloadCode}>
                {k.download}
              </button>
              <button type="button" className="kv-secondary" onClick={printCode}>
                {k.print}
              </button>
            </div>
            <p className="kv-warning">{k.codeWarning}</p>
            <p className="kv-small">{k.codeWhere}</p>
            <button type="button" className="kv-primary" onClick={() => setStep("confirm")}>
              {k.saved}
            </button>
            {laterButton}
          </>
        )}

        {step === "confirm" && (
          <>
            <h2 className="modal-title">{k.confirmTitle}</h2>
            <p className="kv-lead">{k.confirmLead}</p>
            <div className="kv-confirm">
              {positions.map((p, i) => (
                <label key={p}>
                  <span>{k.confirmPos.replace("{n}", String(p + 1))}</span>
                  <input
                    className="modal-field"
                    maxLength={1}
                    autoFocus={i === 0}
                    autoCapitalize="characters"
                    autoComplete="off"
                    value={confirmChars[i]}
                    onChange={(e) => {
                      const next = [...confirmChars];
                      next[i] = e.target.value.slice(-1);
                      setConfirmChars(next);
                    }}
                  />
                </label>
              ))}
            </div>
            {error && <p className="kv-error">{error}</p>}
            <button
              type="button"
              className="kv-primary"
              onClick={confirmCreate}
              disabled={busy || confirmChars.some((c) => !c) || !canonical}
            >
              {busy ? k.creating : k.confirmCta}
            </button>
            <button type="button" className="kv-link" onClick={() => setStep("code")} disabled={busy}>
              {k.back}
            </button>
          </>
        )}

        {step === "open" && (
          <>
            <div className="kv-icon" aria-hidden="true">🔐</div>
            <h2 className="modal-title">{k.openTitle}</h2>
            {notice && <p className="kv-notice">{notice}</p>}
            <p className="kv-lead">{mode === "default" ? k.openLead : k.unlockFirst}</p>
            {canPasskey && slots.some((s) => s.type === "passkey") && (
              <button type="button" className="kv-primary" onClick={openWithPasskey} disabled={busy}>
                {k.openPasskey}
              </button>
            )}
            <form
              className="kv-open-form"
              onSubmit={(e) => {
                e.preventDefault();
                openWithCode();
              }}
            >
              <label className="kv-small" htmlFor="kv-code-input">{k.codeLabel}</label>
              <input
                id="kv-code-input"
                className="modal-field kv-code-input"
                placeholder="XXXX-XXXX-XXXX-XXXX-XXXX-XXXX"
                autoComplete="off"
                autoCapitalize="characters"
                spellCheck={false}
                value={typedCode}
                onChange={(e) => setTypedCode(e.target.value)}
              />
              <button
                type="submit"
                className={slots.some((s) => s.type === "passkey") && canPasskey ? "kv-secondary" : "kv-primary"}
                disabled={busy || !normalizeRecoveryCode(typedCode)}
              >
                {busy ? k.opening : k.openCta}
              </button>
            </form>
            {error && <p className="kv-error">{error}</p>}
            <button type="button" className="kv-link" onClick={startPhone} disabled={busy}>
              {k.phoneCta}
            </button>
            {mode !== "regenerate" && <p className="kv-small">{k.lostCode}</p>}
            {laterButton}
          </>
        )}

        {step === "phone" && (
          <>
            <h2 className="modal-title">{k.phoneTitle}</h2>
            <p className="kv-lead">{k.phoneLead}</p>
            {qr && !qr.expired && <QrCanvas text={qr.text} className="kv-qr" />}
            {qr && !qr.expired && <p className="kv-small">{k.phoneWaiting}</p>}
            {qr?.expired && !error && <p className="kv-error">{k.phoneExpired}</p>}
            {error && <p className="kv-error">{error}</p>}
            {qr?.expired && (
              <button type="button" className="kv-primary" onClick={startPhone} disabled={busy}>
                {k.phoneRetry}
              </button>
            )}
            <button
              type="button"
              className="kv-link"
              onClick={() => {
                closeRoom();
                setError(null);
                if (mode === "receive") later();
                else setStep("open");
              }}
            >
              {mode === "receive" ? k.cancel : k.back}
            </button>
          </>
        )}

        {step === "passkey" && (
          <>
            <div className="kv-icon" aria-hidden="true">👆</div>
            <h2 className="modal-title">{k.passkeyTitle}</h2>
            <p className="kv-lead">{k.passkeyBody}</p>
            {error && <p className="kv-error">{error}</p>}
            <button type="button" className="kv-primary" onClick={createPasskey} disabled={busy}>
              {k.passkeyCta}
            </button>
            <button type="button" className="kv-link" onClick={mode === "addPasskey" ? later : () => setStep("done")} disabled={busy}>
              {mode === "addPasskey" ? k.cancel : k.passkeySkip}
            </button>
          </>
        )}

        {step === "done" && (
          <>
            <div className="kv-icon" aria-hidden="true">✓</div>
            <h2 className="modal-title">{k.doneTitle}</h2>
            {notice && <p className="kv-notice">{notice}</p>}
            <p className="kv-lead">{k.doneBody}</p>
            <button type="button" className="kv-primary" onClick={finish}>
              {k.doneCta}
            </button>
          </>
        )}
      </div>
    </Modal>
  );
}

/** Nome leggibile della passkey nella cassaforte: browser e sistema, niente di più. */
function browserLabel() {
  const ua = navigator.userAgent;
  const browser = /Edg\//.test(ua) ? "Edge" : /Chrome\//.test(ua) ? "Chrome" : /Firefox\//.test(ua) ? "Firefox" : /Safari\//.test(ua) ? "Safari" : "Browser";
  const os = /Windows/.test(ua) ? "Windows" : /Mac OS X/.test(ua) ? "Mac" : /Android/.test(ua) ? "Android" : /iPhone|iPad/.test(ua) ? "iOS" : /Linux/.test(ua) ? "Linux" : "";
  return os ? `${browser} · ${os}` : browser;
}
