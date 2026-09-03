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

/** Formati che la trasformazione in PDF accetta, allineati ad app iOS e Android. */
const IMAGE_MIMES = new Set(["image/jpeg", "image/jpg", "image/png", "image/heic", "image/heif"]);
const IMAGE_EXTENSIONS = ["jpg", "jpeg", "png", "heic", "heif"];

export function isConvertibleImage(document) {
  const mime = (document.mimeType || "").toLowerCase();
  if (IMAGE_MIMES.has(mime)) return true;
  const name = (document.fileName || document.title || "").toLowerCase();
  return IMAGE_EXTENSIONS.some((ext) => name.endsWith(`.${ext}`));
}

/** Lato lungo massimo, come su Android: ~250 dpi su un A4. */
const MAX_IMAGE_SIDE = 3000;

/**
 * Trasforma immagini in un unico PDF, una pagina per immagine.
 *
 * I PNG entro il tetto vengono incorporati così come sono: sono senza perdita,
 * non hanno orientamento EXIF e spesso sono schermate piene di testo, che una
 * ricompressione rovinerebbe. Oltre il tetto vengono ridotti, ma restano PNG:
 * riscriverli in JPEG sfocherebbe proprio il testo che li rende utili.
 *
 * JPEG e HEIC passano invece da un canvas prima di essere incorporati, per due
 * motivi che non si possono aggirare:
 * - `pdf-lib` incorpora il JPEG grezzo e **ignora l'orientamento EXIF**, quindi
 *   una foto verticale finirebbe coricata come succedeva sulle app;
 * - l'HEIC `pdf-lib` non lo conosce affatto, e l'unico modo di leggerlo è
 *   chiedere al browser di decodificarlo.
 *
 * Il passaggio dal canvas costa una ricompressione. È lo stesso compromesso di
 * Android, che le foto le ridisegna comunque.
 *
 * @param {{bytes: ArrayBuffer, mimeType: string, name: string}[]} images
 */
export async function imagesToPdf(images) {
  const { PDFDocument } = await import("pdf-lib");
  const pdf = await PDFDocument.create();

  for (const image of images) {
    const embedded = await embedImage(pdf, image);
    const page = pdf.addPage([embedded.width, embedded.height]);
    page.drawImage(embedded, {
      x: 0,
      y: 0,
      width: embedded.width,
      height: embedded.height,
    });
  }

  return pdf.save();
}

function isPng(image) {
  return (image.mimeType || "").toLowerCase() === "image/png" ||
    (image.name || "").toLowerCase().endsWith(".png");
}

async function embedImage(pdf, image) {
  if (isPng(image)) {
    // Solo i PNG davvero grandi passano dal canvas: sotto al tetto si incorpora
    // il file originale, senza toccarlo.
    const size = pngSize(image.bytes);
    if (!size || Math.max(size.width, size.height) <= MAX_IMAGE_SIDE) {
      return pdf.embedPng(image.bytes);
    }
    return pdf.embedPng(await redraw(image, "image/png"));
  }
  return pdf.embedJpg(await redraw(image, "image/jpeg", 0.92));
}

/**
 * Larghezza e altezza lette dall'intestazione IHDR, senza decodificare
 * l'immagine: un PNG da 8000px costerebbe decine di MB solo per misurarlo.
 *
 * Struttura: 8 byte di firma, poi il chunk IHDR (4 lunghezza + 4 tipo), quindi
 * larghezza e altezza come interi a 32 bit big-endian.
 */
function pngSize(bytes) {
  const view = new DataView(bytes instanceof ArrayBuffer ? bytes : bytes.buffer);
  if (view.byteLength < 24) return null;
  if (view.getUint32(0) !== 0x89504e47) return null; // non è un PNG
  return { width: view.getUint32(16), height: view.getUint32(20) };
}

/**
 * Decodifica col browser, riduce entro il tetto e riscrive nel formato chiesto.
 * `createImageBitmap` applica l'orientamento EXIF, quindi la foto esce dritta.
 *
 * Se il browser non sa decodificare il formato — è il caso dell'HEIC fuori da
 * Safari — l'errore dice quale file e perché, invece di produrre una pagina vuota.
 */
async function redraw(image, outputType, quality) {
  const blob = new Blob([image.bytes], { type: image.mimeType || "image/jpeg" });

  let bitmap;
  try {
    bitmap = await createImageBitmap(blob);
  } catch {
    throw new Error(
      `Questo browser non sa leggere «${image.name}». I file HEIC si convertono dall'app KidBox.`
    );
  }

  const scale = Math.min(1, MAX_IMAGE_SIDE / Math.max(bitmap.width, bitmap.height));
  const width = Math.max(1, Math.round(bitmap.width * scale));
  const height = Math.max(1, Math.round(bitmap.height * scale));

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  // Il JPEG non ha trasparenza: senza fondo bianco le zone trasparenti
  // diventerebbero nere. Sul PNG il fondo non si mette, altrimenti si
  // butterebbe via la trasparenza che il formato conserva.
  if (outputType !== "image/png") {
    context.fillStyle = "#ffffff";
    context.fillRect(0, 0, width, height);
  }
  context.drawImage(bitmap, 0, 0, width, height);
  bitmap.close();

  const output = await new Promise((resolve) => canvas.toBlob(resolve, outputType, quality));
  if (!output) throw new Error(`Conversione non riuscita per «${image.name}».`);
  return output.arrayBuffer();
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
