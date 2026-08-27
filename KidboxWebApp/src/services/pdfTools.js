/**
 * Strumenti PDF lato browser. Le librerie sono caricate con import dinamico:
 * pesano parecchio e servono solo a chi usa unione o sblocco, non a chi apre
 * la sezione Documenti.
 */

/**
 * Unisce più PDF in uno, nell'ordine ricevuto — equivalente di mergePDFs
 * (DocumentFolderViewModel+Merge) che su iOS usa PDFKit.
 */
export async function mergePdfs(buffers) {
  const { PDFDocument } = await import("pdf-lib");
  const merged = await PDFDocument.create();

  for (const buffer of buffers) {
    // `ignoreEncryption` copre i PDF con sole restrizioni (owner password):
    // senza, pdf-lib rifiuterebbe di aprirli anche se sono leggibili.
    const source = await PDFDocument.load(buffer, { ignoreEncryption: true });
    const pages = await merged.copyPages(source, source.getPageIndices());
    pages.forEach((page) => merged.addPage(page));
  }

  return merged.save();
}

/**
 * Rimuove la protezione da un PDF, restituendo i byte di una copia apribile
 * senza password.
 *
 * Due strade, in ordine di qualità del risultato:
 *
 * 1. Se il PDF ha solo restrizioni (stampa/copia) e non una password di
 *    apertura, pdf-lib lo riscrive tale e quale: risultato identico all'originale.
 *
 * 2. Se serve la password per aprirlo, pdf-lib non sa decifrarlo. Si passa da
 *    pdf.js, che la password la gestisce, ma può solo *disegnare* le pagine:
 *    la copia risultante è quindi rasterizzata e il testo non resta
 *    selezionabile. È un limite del browser, non una scelta: su iPhone PDFKit
 *    produce una copia che conserva il testo.
 *
 * @returns {Promise<{bytes: Uint8Array, rasterized: boolean}>}
 */
export async function unlockPdf(buffer, password) {
  const { PDFDocument } = await import("pdf-lib");

  // Strada 1: nessuna password di apertura.
  try {
    const source = await PDFDocument.load(buffer, { ignoreEncryption: true });
    const bytes = await source.save();
    return { bytes, rasterized: false };
  } catch {
    // Serve davvero la password: si prosegue con pdf.js.
  }

  const pdfjs = await import("pdfjs-dist");
  pdfjs.GlobalWorkerOptions.workerSrc = (
    await import("pdfjs-dist/build/pdf.worker.min.mjs?url")
  ).default;

  let pdf;
  try {
    pdf = await pdfjs.getDocument({ data: buffer, password }).promise;
  } catch (err) {
    if (err?.name === "PasswordException") {
      const wrong = new Error("wrong-password");
      wrong.code = "wrong-password";
      throw wrong;
    }
    throw err;
  }

  const out = await PDFDocument.create();
  const SCALE = 2; // compromesso fra leggibilità e peso del file

  for (let i = 1; i <= pdf.numPages; i += 1) {
    const page = await pdf.getPage(i);
    const viewport = page.getViewport({ scale: SCALE });

    const canvas = document.createElement("canvas");
    canvas.width = viewport.width;
    canvas.height = viewport.height;
    await page.render({ canvasContext: canvas.getContext("2d"), viewport }).promise;

    const pngBytes = await new Promise((resolve) =>
      canvas.toBlob(async (blob) => resolve(new Uint8Array(await blob.arrayBuffer())), "image/png")
    );

    const image = await out.embedPng(pngBytes);
    const target = out.addPage([viewport.width / SCALE, viewport.height / SCALE]);
    target.drawImage(image, {
      x: 0,
      y: 0,
      width: target.getWidth(),
      height: target.getHeight(),
    });
  }

  return { bytes: await out.save(), rasterized: true };
}
