import { useEffect } from "react";
import { useSearchParams } from "react-router-dom";

/**
 * Apre una voce dall'indirizzo: `?apri=<id>` (più `tipo` dove una pagina ha
 * voci di generi diversi). Lo usano i link dell'assistente (`agentLinks.js`).
 *
 * `find(id, params)` cerca la voce nei dati della pagina; finché non c'è (la
 * lettura non è ancora arrivata) non succede niente e si riprova al giro
 * dopo. Trovata, `open(voce)` la apre e il parametro sparisce, così chiudere
 * il dettaglio non la riapre.
 */
export function useOpenParam(find, open) {
  const [params, setParams] = useSearchParams();
  const id = params.get("apri");
  const item = id ? find(id, params) : null;
  useEffect(() => {
    if (!id || !item) return;
    open(item, params);
    // `modulo` resta: Salute lo tiene nell'indirizzo per conto suo.
    const next = new URLSearchParams(params);
    next.delete("apri");
    next.delete("tipo");
    next.delete("persona");
    setParams(next, { replace: true });
    // `item` cambia identità a ogni lettura: basta l'id.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, Boolean(item)]);
}
