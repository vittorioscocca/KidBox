import { useEffect, useState } from "react";
import { useAuth } from "../AuthContext";
import { useFamily } from "../FamilyContext";
import KeyVaultPrompt from "./KeyVaultPrompt";
import { getLocalVault, keyVaultFlags } from "../services/familyKeyVault";

const dismissedKey = (uid) => `kb_vaultLater_${uid}`;

/**
 * Promemoria della cassaforte dentro l'app web (piano v2, sezione 4 ter).
 *
 * Compare solo con l'interruttore `config/keyVault` acceso per questo utente,
 * se il browser non ha ancora la chiave personale. «Più tardi» vale per la
 * sessione del browser; con `enforce` non c'è. Non blocca niente: finché c'è
 * la v1 le pagine leggono la chiave da lì.
 */
export default function KeyVaultGate() {
  const { user } = useAuth();
  const { families } = useFamily();
  const [state, setState] = useState(null); // null | { enforce }

  useEffect(() => {
    if (!user || !families) return undefined;
    let cancelled = false;
    (async () => {
      const flags = await keyVaultFlags(user.uid);
      if (!flags.active || cancelled) return;
      if (await getLocalVault(user.uid)) return;
      let later = false;
      try {
        later = sessionStorage.getItem(dismissedKey(user.uid)) === "1";
      } catch {
        /* storage negato: si richiede */
      }
      if (later && !flags.enforce) return;
      if (!cancelled) setState({ enforce: flags.enforce });
    })();
    return () => {
      cancelled = true;
    };
  }, [user, families]);

  if (!state || !user) return null;
  return (
    <KeyVaultPrompt
      user={user}
      familyIds={(families || []).map((f) => f.id)}
      allowLater={!state.enforce}
      onDone={() => setState(null)}
      onLater={() => {
        try {
          sessionStorage.setItem(dismissedKey(user.uid), "1");
        } catch {
          /* niente */
        }
        setState(null);
      }}
    />
  );
}
