/**
 * Regole Storage: chi è «membro» per i file di una famiglia.
 * Uso (dalla radice del repo):
 *   npx firebase-tools emulators:exec --config firebase.storage-test.json --only firestore,storage --project kidbox-rules-test "node firestore-tests/storage.test.js"
 *   (serve Java 21: JAVA_HOME sul JBR di Android Studio)
 */
const fs = require("node:fs");
const path = require("node:path");
const { initializeTestEnvironment, assertSucceeds, assertFails } = require("@firebase/rules-unit-testing");
const { doc, setDoc } = require("firebase/firestore");
const { ref, uploadBytes, getBytes, deleteObject } = require("firebase/storage");

const root = path.join(__dirname, "..");
const FID = "fam1";
const members = {
  attivo: { uid: "attivo", role: "member" },
  proprietario: { uid: "proprietario", role: "owner" }, // senza isDeleted, come lo creano iOS e web
  cancellato: { uid: "cancellato", role: "member", isDeleted: true },
  senzaRuolo: { displayName: "Ricreato", updatedAt: new Date() }, // ricreato da un aggiornamento del nome
  falso: { uid: "falso", role: "member", isDeleted: false },
};
const paths = ["documents/a.kbenc", "photos/p/x.kbenc", "chat/m/1.kbenc", "wallet/t/ticket.pdf.kbenc", "hero/hero.jpg", "avatars/attivo"];

(async () => {
  const env = await initializeTestEnvironment({
    projectId: "kidbox-rules-test",
    firestore: { rules: fs.readFileSync(path.join(root, "firestore.rules"), "utf8") },
    storage: { rules: fs.readFileSync(path.join(root, "storage.rules"), "utf8") },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `families/${FID}`), { ownerUid: "proprietario" });
    for (const [uid, data] of Object.entries(members)) await setDoc(doc(ctx.firestore(), `families/${FID}/members/${uid}`), data);
    for (const p of paths) await uploadBytes(ref(ctx.storage(), `families/${FID}/${p}`), new Uint8Array([1, 2, 3]));
    await uploadBytes(ref(ctx.storage(), "users/attivo/avatar.jpg"), new Uint8Array([1]));
  });
  let pass = 0, fail = 0;
  const check = async (name, p) => { try { await p; pass++; } catch (e) { fail++; console.log("KO", name, "—", String(e.message).slice(0, 120)); } };
  const st = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).storage();
  for (const uid of ["attivo", "proprietario", "falso"]) {
    for (const p of paths) await check(`${uid} legge ${p}`, assertSucceeds(getBytes(ref(st(uid), `families/${FID}/${p}`))));
    await check(`${uid} scrive`, assertSucceeds(uploadBytes(ref(st(uid), `families/${FID}/documents/nuovo-${uid}.kbenc`), new Uint8Array([9]))));
  }
  for (const uid of ["cancellato", "senzaRuolo", "estraneo", null]) {
    for (const p of paths) await check(`${uid} NON legge ${p}`, assertFails(getBytes(ref(st(uid), `families/${FID}/${p}`))));
    await check(`${uid} NON scrive`, assertFails(uploadBytes(ref(st(uid), `families/${FID}/documents/x-${uid}.kbenc`), new Uint8Array([9]))));
    await check(`${uid} NON cancella`, assertFails(deleteObject(ref(st(uid), `families/${FID}/documents/a.kbenc`))));
  }
  await check("avatar personale: il proprietario del percorso legge", assertSucceeds(getBytes(ref(st("attivo"), "users/attivo/avatar.jpg"))));
  await check("avatar personale: un altro NON legge", assertFails(getBytes(ref(st("falso"), "users/attivo/avatar.jpg"))));
  await check("percorso non previsto: negato anche al membro", assertFails(uploadBytes(ref(st("attivo"), `families/${FID}/altro/x`), new Uint8Array([1]))));
  await env.cleanup();
  console.log(`\nStorage rules: ${pass} ok, ${fail} falliti`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
