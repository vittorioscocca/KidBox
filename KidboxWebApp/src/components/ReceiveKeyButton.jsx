// «Ricevi la chiave con un QR» nelle schermate «chiave mancante» (piano v2,
// sezione 3.2): compare solo se la cassaforte v2 è accesa per questo utente,
// apre il QR da far inquadrare a un proprio dispositivo o a un familiare e,
// arrivata la chiave, ricarica la pagina così i contenuti si decifrano.
// Gemello di FamilyKeyMissingGate su iOS e Android.
import { useEffect, useState } from "react";
import { useAuth } from "../AuthContext";
import { useFamily } from "../FamilyContext";
import { useTranslation } from "../i18n/LocaleContext";
import { keyVaultFlags } from "../services/familyKeyVault";
import KeyVaultPrompt from "./KeyVaultPrompt";

export default function ReceiveKeyButton() {
  const { user } = useAuth();
  const { families } = useFamily();
  const { t } = useTranslation();
  const [active, setActive] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!user?.uid) return;
    keyVaultFlags(user.uid).then((f) => setActive(!!f.active)).catch(() => setActive(false));
  }, [user?.uid]);

  if (!active || !user) return null;
  return (
    <>
      <button type="button" className="receive-key-btn" onClick={() => setOpen(true)}>
        {t.keyVault.secReceive}
      </button>
      {open && (
        <KeyVaultPrompt
          user={user}
          familyIds={(families || []).map((f) => f.id)}
          mode="receive"
          onDone={() => window.location.reload()}
          onLater={() => setOpen(false)}
        />
      )}
    </>
  );
}
