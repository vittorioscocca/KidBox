import { useEffect, useMemo, useRef, useState } from "react";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import {
  deleteHomeItem,
  deleteHousePayment,
  homeFolderId,
  homeItemTag,
  housePaymentTag,
  ITEM_CATEGORIES,
  itemCategory,
  listenHome,
  paymentType,
  saveHomeItem,
  saveHousePayment,
} from "../services/homeItems";
import { fetchDocumentBlob, uploadDocument } from "../services/documents";
import { ensureFolder, listenTaggedDocuments } from "../services/attachments";
import { formatAmount } from "../expenseCategories";
import HomeItemModal from "../components/HomeItemModal";
import HousePaymentModal from "../components/HousePaymentModal";
import "./Casa.css";

export default function Casa() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();
  const h = t.house;
  const fileRef = useRef(null);

  const [items, setItems] = useState([]);
  const [payments, setPayments] = useState([]);
  const [attachments, setAttachments] = useState(new Map());
  const [error, setError] = useState(null);

  const [selected, setSelected] = useState(null); // { type: "item"|"payment", id }
  const [editingItem, setEditingItem] = useState(null);
  const [editingPayment, setEditingPayment] = useState(null);
  const [pendingTag, setPendingTag] = useState(null);

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    return listenHome({
      familyId: currentFamilyId,
      onChange: ({ items: it, payments: pa }) => {
        setItems(it);
        setPayments(pa);
      },
      onError: (err) => setError(err.message),
    });
  }, [currentFamilyId]);

  // Gli allegati di Casa hanno gli stessi tag di quelli degli animali, quindi
  // riusa lo stesso ascoltatore: cambia solo quale prefisso si guarda.
  useEffect(() => {
    if (!currentFamilyId) return undefined;
    return listenTaggedDocuments({
      familyId: currentFamilyId,
      prefixes: ["homeItem:", "housePayment:"],
      onChange: setAttachments,
      onError: (err) => setError(err.message),
    });
  }, [currentFamilyId]);

  const now = Date.now();

  const grouped = useMemo(
    () =>
      ITEM_CATEGORIES.map((c) => ({
        category: c,
        rows: items.filter((i) => i.categoryRaw === c.raw),
      })).filter((g) => g.rows.length > 0),
    [items]
  );

  const openItem = items.find((x) => selected?.type === "item" && x.id === selected.id) || null;
  const openPayment =
    payments.find((x) => selected?.type === "payment" && x.id === selected.id) || null;

  const fmt = (millis) =>
    millis
      ? new Date(millis).toLocaleDateString(locale === "en" ? "en-US" : "it-IT", {
          day: "2-digit",
          month: "short",
          year: "numeric",
        })
      : null;

  /** Scaduta, in scadenza entro due mesi, o niente da segnalare. */
  const state = (millis) => {
    if (!millis) return null;
    if (millis < now) return "expired";
    if (millis - now < 60 * 24 * 60 * 60 * 1000) return "soon";
    return null;
  };

  /** La data che conta per un oggetto: la più vicina fra garanzia e manutenzione. */
  const itemDue = (item) =>
    [item.warrantyExpiryDate, item.nextServiceDate].filter(Boolean).sort((a, b) => a - b)[0] || null;

  const removeItem = async (id) => {
    if (!window.confirm(h.confirmDelete)) return;
    await deleteHomeItem({ familyId: currentFamilyId, userId: user.uid, id });
    setSelected(null);
  };

  const removePayment = async (payment) => {
    if (!window.confirm(h.confirmDeletePayment)) return;
    await deleteHousePayment({
      familyId: currentFamilyId,
      userId: user.uid,
      id: payment.id,
      linkedExpenseId: payment.linkedExpenseId,
    });
    setSelected(null);
  };

  const pickAttachment = (tag) => {
    setPendingTag(tag);
    fileRef.current?.click();
  };

  const uploadAttachment = async (file) => {
    if (!file || !pendingTag) return;
    try {
      const id = await ensureFolder({
        familyId: currentFamilyId,
        userId: user.uid,
        id: homeFolderId(currentFamilyId),
        title: h.title,
      });
      await uploadDocument({
        familyId: currentFamilyId,
        userId: user.uid,
        file,
        categoryId: id,
        notes: pendingTag,
      });
    } catch (err) {
      setError(err.message);
    } finally {
      setPendingTag(null);
    }
  };

  const openAttachment = async (docData) => {
    try {
      const blob = await fetchDocumentBlob({
        familyId: currentFamilyId,
        userId: user.uid,
        document: docData,
      });
      window.open(URL.createObjectURL(blob), "_blank", "noopener");
    } catch (err) {
      setError(err.message);
    }
  };

  const attachmentList = (tag) => (
    <div className="an-attachments">
      {(attachments.get(tag) || []).map((d) => (
        <button key={d.id} className="an-attachment" onClick={() => openAttachment(d)}>
          📎 {d.title || d.fileName}
        </button>
      ))}
      <button className="an-attachment add" onClick={() => pickAttachment(tag)}>
        + {h.addAttachment}
      </button>
    </div>
  );

  return (
    <div className="casa-page">
      <header className="pw-header">
        <h1>{h.title}</h1>
        <div className="pw-toolbar">
          <button onClick={() => setEditingPayment({})}>+ {h.addPayment}</button>
          <button className="pw-btn-primary" onClick={() => setEditingItem({})}>
            + {h.addItem}
          </button>
        </div>
      </header>

      {error && <p className="error">{error}</p>}

      {items.length === 0 && payments.length === 0 ? (
        <p className="pw-empty">{h.empty}</p>
      ) : (
        <>
          {grouped.map(({ category, rows }) => (
            <section key={category.raw} className="casa-group">
              <h3>
                {category.emoji} {locale === "en" ? category.pluralEn : category.plural}
              </h3>
              <div className="casa-grid">
                {rows.map((item) => {
                  const due = itemDue(item);
                  const st = state(due);
                  return (
                    <button
                      key={item.id}
                      className="casa-card"
                      onClick={() => setSelected({ type: "item", id: item.id })}
                    >
                      <span className="casa-name">{item.name}</span>
                      <span className="casa-meta">
                        {[item.brand, item.model].filter(Boolean).join(" · ") ||
                          (locale === "en" ? category.en : category.it)}
                      </span>
                      {due && (
                        <span className={"casa-due" + (st ? " " + st : "")}>
                          {st === "expired" ? h.expiredLabel : h.expiringLabel}: {fmt(due)}
                        </span>
                      )}
                    </button>
                  );
                })}
              </div>
            </section>
          ))}

          {payments.length > 0 && (
            <section className="casa-group">
              <h3>💰 {h.payments}</h3>
              <div className="casa-grid">
                {payments.map((p) => {
                  const ty = paymentType(p.typeRaw);
                  const st = state(p.dataScadenza);
                  return (
                    <button
                      key={p.id}
                      className="casa-card"
                      onClick={() => setSelected({ type: "payment", id: p.id })}
                    >
                      <span className="casa-name">
                        {ty.emoji} {p.name}
                      </span>
                      <span className="casa-meta">
                        {[
                          locale === "en" ? ty.en : ty.it,
                          p.subtypeRaw,
                          p.fornitore,
                        ]
                          .filter(Boolean)
                          .join(" · ")}
                      </span>
                      <span className="casa-row-bottom">
                        {p.importo != null && (
                          <span className="casa-amount">{formatAmount(p.importo, locale)}</span>
                        )}
                        {p.dataScadenza && (
                          <span className={"casa-due" + (st ? " " + st : "")}>{fmt(p.dataScadenza)}</span>
                        )}
                      </span>
                    </button>
                  );
                })}
              </div>
            </section>
          )}
        </>
      )}

      <input
        ref={fileRef}
        type="file"
        hidden
        onChange={(e) => {
          const f = e.target.files?.[0];
          e.target.value = "";
          if (f) uploadAttachment(f);
        }}
      />

      {openItem && (
        <div className="pw-detail-overlay" onClick={() => setSelected(null)}>
          <aside className="pw-detail" onClick={(e) => e.stopPropagation()}>
            <header>
              <h2>
                {itemCategory(openItem.categoryRaw).emoji} {openItem.name}
              </h2>
              <button onClick={() => setSelected(null)}>✕</button>
            </header>
            <Row
              label={h.category}
              value={
                locale === "en"
                  ? itemCategory(openItem.categoryRaw).en
                  : itemCategory(openItem.categoryRaw).it
              }
            />
            <Row label={h.brand} value={openItem.brand} />
            <Row label={h.model} value={openItem.model} />
            <Row label={h.serialNumber} value={openItem.serialNumber} />
            <Row label={h.purchaseDate} value={fmt(openItem.purchaseDate)} />
            <Row label={h.warranty} value={fmt(openItem.warrantyExpiryDate)} />
            <Row label={h.nextService} value={fmt(openItem.nextServiceDate)} />
            <Row
              label={h.servicePeriod}
              value={openItem.servicePeriodMonths ? String(openItem.servicePeriodMonths) : null}
            />
            <Row label={h.notes} value={openItem.notes} />

            <h3 className="an-section">{h.attachments}</h3>
            {attachmentList(homeItemTag(openItem.id))}

            <div className="pw-form-actions">
              <button className="pw-danger" onClick={() => removeItem(openItem.id)}>
                {h.delete}
              </button>
              <button
                className="pw-btn-primary"
                onClick={() => {
                  setEditingItem(openItem);
                  setSelected(null);
                }}
              >
                {h.edit}
              </button>
            </div>
          </aside>
        </div>
      )}

      {openPayment && (
        <div className="pw-detail-overlay" onClick={() => setSelected(null)}>
          <aside className="pw-detail" onClick={(e) => e.stopPropagation()}>
            <header>
              <h2>
                {paymentType(openPayment.typeRaw).emoji} {openPayment.name}
              </h2>
              <button onClick={() => setSelected(null)}>✕</button>
            </header>
            <Row
              label={h.type}
              value={
                locale === "en"
                  ? paymentType(openPayment.typeRaw).en
                  : paymentType(openPayment.typeRaw).it
              }
            />
            <Row label={h.subtype} value={openPayment.subtypeRaw} />
            <Row
              label={h.amount}
              value={openPayment.importo != null ? formatAmount(openPayment.importo, locale) : null}
            />
            <Row label={h.dueDate} value={fmt(openPayment.dataScadenza)} />
            <Row
              label={h.monthlyDay}
              value={
                openPayment.giornoDiScadenzaMensile
                  ? String(openPayment.giornoDiScadenzaMensile)
                  : null
              }
            />
            <Row label={h.contractEnd} value={fmt(openPayment.dataScadenzaContratto)} />
            <Row label={h.supplier} value={openPayment.fornitore} />
            <Row label={h.notes} value={openPayment.note} />
            {openPayment.linkedExpenseId && <p className="pw-hint">💶 {h.linkedExpense}</p>}

            <h3 className="an-section">{h.attachments}</h3>
            {attachmentList(housePaymentTag(openPayment.id))}

            <div className="pw-form-actions">
              <button className="pw-danger" onClick={() => removePayment(openPayment)}>
                {h.delete}
              </button>
              <button
                className="pw-btn-primary"
                onClick={() => {
                  setEditingPayment(openPayment);
                  setSelected(null);
                }}
              >
                {h.edit}
              </button>
            </div>
          </aside>
        </div>
      )}

      {editingItem && (
        <HomeItemModal
          item={editingItem}
          locale={locale}
          onSave={(item) => saveHomeItem({ familyId: currentFamilyId, userId: user.uid, item })}
          onClose={() => setEditingItem(null)}
        />
      )}

      {editingPayment && (
        <HousePaymentModal
          payment={editingPayment}
          locale={locale}
          onSave={(payment) =>
            saveHousePayment({ familyId: currentFamilyId, userId: user.uid, payment })
          }
          onClose={() => setEditingPayment(null)}
        />
      )}
    </div>
  );
}

/** Riga del pannello di dettaglio. Fuori dal componente: dichiararla dentro il
 *  rendering la ricrea a ogni passata e rimonta tutte le righe. */
function Row({ label, value }) {
  if (!value) return null;
  return (
    <div className="pw-detail-row">
      <span className="pw-detail-label">{label}</span>
      <span className="pw-detail-value">{value}</span>
    </div>
  );
}
