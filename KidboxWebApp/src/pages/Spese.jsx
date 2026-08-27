import { useEffect, useMemo, useState } from "react";
import {
  Timestamp,
  collection,
  deleteField,
  doc,
  onSnapshot,
  query,
  serverTimestamp,
  setDoc,
  where,
} from "firebase/firestore";
import { db } from "../firebase";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import {
  EXPENSE_CATEGORIES,
  PERIODS,
  categoryFromId,
  categoryId,
  formatAmount,
  periodRange,
} from "../expenseCategories";
import Modal from "../components/Modal";
import "./Spese.css";

function expensesCol(familyId) {
  return collection(db, "families", familyId, "expenses");
}

function toDateInput(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export default function Spese() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();

  const [expenses, setExpenses] = useState([]);
  const [error, setError] = useState(null);
  const [period, setPeriod] = useState("oneMonth");
  const [customStart, setCustomStart] = useState(() =>
    toDateInput(new Date(Date.now() - 30 * 864e5))
  );
  const [customEnd, setCustomEnd] = useState(() => toDateInput(new Date()));
  const [categoryFilter, setCategoryFilter] = useState(null);
  const [editing, setEditing] = useState(null);
  const [creating, setCreating] = useState(false);

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    const q = query(expensesCol(currentFamilyId), where("isDeleted", "==", false));
    return onSnapshot(
      q,
      (snap) => setExpenses(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (err) => setError(err.message)
    );
  }, [currentFamilyId]);

  const range = useMemo(() => {
    if (period !== "custom") return periodRange(period);
    const start = new Date(customStart);
    start.setHours(0, 0, 0, 0);
    const end = new Date(customEnd);
    end.setHours(23, 59, 59, 999);
    return { start, end };
  }, [period, customStart, customEnd]);

  const inPeriod = useMemo(
    () =>
      expenses
        .filter((e) => {
          const d = e.date?.toDate?.();
          return d && d >= range.start && d <= range.end;
        })
        .sort((a, b) => (b.date?.toMillis?.() ?? 0) - (a.date?.toMillis?.() ?? 0)),
    [expenses, range]
  );

  const visible = useMemo(
    () =>
      categoryFilter
        ? inPeriod.filter((e) => e.categoryId === categoryFilter)
        : inPeriod,
    [inPeriod, categoryFilter]
  );

  const total = useMemo(
    () => visible.reduce((sum, e) => sum + (Number(e.amount) || 0), 0),
    [visible]
  );

  /** Ripartizione per categoria sul periodo, ordinata per importo. */
  const bySlice = useMemo(() => {
    const map = new Map();
    inPeriod.forEach((e) => {
      const key = e.categoryId ?? "none";
      map.set(key, (map.get(key) ?? 0) + (Number(e.amount) || 0));
    });
    const sum = [...map.values()].reduce((a, b) => a + b, 0) || 1;
    return [...map.entries()]
      .map(([key, value]) => {
        const cat = key === "none" ? null : categoryFromId(currentFamilyId, key);
        return {
          key,
          label: cat?.name ?? t.expenses.noCategory,
          color: cat?.color ?? "#9E9E9E",
          icon: cat?.icon ?? "•",
          amount: value,
          percent: (value / sum) * 100,
        };
      })
      .sort((a, b) => b.amount - a.amount);
  }, [inPeriod, currentFamilyId, t]);

  /** Totale per mese nel periodo: barre proporzionali al mese più alto. */
  const byMonth = useMemo(() => {
    const map = new Map();
    inPeriod.forEach((e) => {
      const d = e.date?.toDate?.();
      if (!d) return;
      const key = `${d.getFullYear()}-${d.getMonth()}`;
      if (!map.has(key)) map.set(key, { year: d.getFullYear(), month: d.getMonth(), total: 0 });
      map.get(key).total += Number(e.amount) || 0;
    });
    const list = [...map.values()].sort(
      (a, b) => a.year - b.year || a.month - b.month
    );
    const max = Math.max(...list.map((m) => m.total), 1);
    return list.map((m) => ({ ...m, ratio: m.total / max }));
  }, [inPeriod]);

  const monthShort = (year, month) =>
    new Intl.DateTimeFormat(locale === "en" ? "en-US" : "it-IT", { month: "short" })
      .format(new Date(year, month, 1));

  const save = async (values) => {
    const id = editing?.id ?? crypto.randomUUID();
    const payload = {
      id,
      familyId: currentFamilyId,
      title: values.title,
      amount: values.amount,
      date: Timestamp.fromDate(values.date),
      categoryId: values.categoryId ?? deleteField(),
      notes: values.notes || deleteField(),
      isDeleted: false,
      updatedBy: user.uid,
      updatedAt: serverTimestamp(),
    };
    // Creatore e data di creazione appartengono a chi ha inserito la spesa.
    if (!editing) {
      payload.createdByUid = user.uid;
      payload.createdAt = serverTimestamp();
    }
    try {
      await setDoc(doc(expensesCol(currentFamilyId), id), payload, { merge: true });
      setEditing(null);
      setCreating(false);
    } catch (err) {
      setError(err.message);
    }
  };

  const remove = async (expense) => {
    if (!window.confirm(t.expenses.deleteConfirm)) return;
    try {
      await setDoc(
        doc(expensesCol(currentFamilyId), expense.id),
        { isDeleted: true, updatedBy: user.uid, updatedAt: serverTimestamp() },
        { merge: true }
      );
      setEditing(null);
    } catch (err) {
      setError(err.message);
    }
  };

  return (
    <div className="expenses-page">
      <div className="overview-header">
        <h1>{t.expenses.title}</h1>
        <button className="toolbar-add" onClick={() => setCreating(true)} title={t.expenses.new}>
          +
        </button>
      </div>

      <div className="seg-control period-picker">
        {PERIODS.map((p) => (
          <button
            key={p}
            className={"seg-btn" + (period === p ? " active" : "")}
            onClick={() => setPeriod(p)}
          >
            {t.expenses.periods[p]}
          </button>
        ))}
      </div>

      {period === "custom" && (
        <div className="custom-range">
          <label>
            {t.expenses.from}
            <input
              type="date"
              value={customStart}
              onChange={(e) => setCustomStart(e.target.value)}
            />
          </label>
          <label>
            {t.expenses.to}
            <input
              type="date"
              value={customEnd}
              onChange={(e) => setCustomEnd(e.target.value)}
            />
          </label>
        </div>
      )}

      {error && <p className="error">{error}</p>}

      <div className="total-card">
        <span className="total-label">{t.expenses.total}</span>
        <span className="total-value">{formatAmount(total, locale)}</span>
        <span className="total-count">{t.expenses.count(visible.length)}</span>
      </div>

      {inPeriod.length === 0 ? (
        <div className="docs-empty">
          <div className="empty-icon">💶</div>
          <strong>{t.expenses.empty}</strong>
          <p>{t.expenses.emptyHint}</p>
        </div>
      ) : (
        <>
          {byMonth.length > 1 && (
            <section className="chart-block">
              <h3>{t.expenses.byMonth}</h3>
              <div className="bar-chart">
                {byMonth.map((m) => (
                  <div key={`${m.year}-${m.month}`} className="bar-col">
                    <span className="bar-value">{Math.round(m.total)}</span>
                    <div className="bar" style={{ height: `${Math.max(4, m.ratio * 100)}%` }} />
                    <span className="bar-label">{monthShort(m.year, m.month)}</span>
                  </div>
                ))}
              </div>
            </section>
          )}

          <section className="chart-block">
            <h3>{t.expenses.byCategory}</h3>
            <div className="slices">
              {bySlice.map((s) => (
                <button
                  key={s.key}
                  className={
                    "slice" + (categoryFilter === s.key ? " active" : "")
                  }
                  onClick={() =>
                    setCategoryFilter(
                      categoryFilter === s.key ? null : s.key === "none" ? null : s.key
                    )
                  }
                >
                  <span className="slice-icon">{s.icon}</span>
                  <span className="slice-name">{s.label}</span>
                  <span className="slice-bar">
                    <span style={{ width: `${s.percent}%`, background: s.color }} />
                  </span>
                  <span className="slice-amount">{formatAmount(s.amount, locale)}</span>
                </button>
              ))}
            </div>
          </section>

          <ul className="expense-list">
            {visible.map((e) => {
              const cat = categoryFromId(currentFamilyId, e.categoryId);
              const d = e.date?.toDate?.();
              return (
                <li key={e.id}>
                  <span
                    className="expense-icon"
                    style={{ background: `${cat?.color ?? "#9E9E9E"}22` }}
                  >
                    {cat?.icon ?? "•"}
                  </span>
                  <button className="expense-main" onClick={() => setEditing(e)}>
                    <span className="expense-title">{e.title}</span>
                    <span className="expense-meta">
                      {cat?.name ?? t.expenses.noCategory}
                      {d &&
                        ` · ${new Intl.DateTimeFormat(
                          locale === "en" ? "en-US" : "it-IT",
                          { day: "2-digit", month: "2-digit", year: "2-digit" }
                        ).format(d)}`}
                    </span>
                  </button>
                  <span className="expense-amount">{formatAmount(e.amount, locale)}</span>
                </li>
              );
            })}
          </ul>
        </>
      )}

      {(creating || editing) && (
        <ExpenseModal
          familyId={currentFamilyId}
          expense={editing}
          onCancel={() => {
            setCreating(false);
            setEditing(null);
          }}
          onSave={save}
          onDelete={editing ? () => remove(editing) : null}
        />
      )}
    </div>
  );
}

function ExpenseModal({ familyId, expense, onCancel, onSave, onDelete }) {
  const { t } = useTranslation();
  const [title, setTitle] = useState(expense?.title ?? "");
  const [amount, setAmount] = useState(
    expense?.amount != null ? String(expense.amount) : ""
  );
  const [date, setDate] = useState(
    toDateInput(expense?.date?.toDate?.() ?? new Date())
  );
  const [slug, setSlug] = useState(
    categoryFromId(familyId, expense?.categoryId)?.slug ?? null
  );
  const [notes, setNotes] = useState(expense?.notes ?? "");

  const value = Number(String(amount).replace(",", "."));
  const valid = title.trim() && Number.isFinite(value) && value > 0;

  return (
    <Modal onClose={onCancel}>
      <div className="modal-header">
        <button className="modal-text-btn" onClick={onCancel}>
          {t.expenses.cancel}
        </button>
        <button
          className="modal-save-btn"
          disabled={!valid}
          onClick={() =>
            onSave({
              title: title.trim(),
              amount: value,
              date: new Date(`${date}T12:00:00`),
              categoryId: slug ? categoryId(familyId, slug) : null,
              notes: notes.trim(),
            })
          }
        >
          {t.expenses.save}
        </button>
      </div>
      <div className="modal-title">
        {expense ? t.expenses.edit : t.expenses.new}
      </div>

      <input
        className="modal-field"
        placeholder={t.expenses.titlePlaceholder}
        value={title}
        autoFocus
        onChange={(e) => setTitle(e.target.value)}
      />

      <div className="modal-row-fields">
        <label>
          {t.expenses.amount}
          <input
            className="modal-field"
            type="number"
            inputMode="decimal"
            step="0.01"
            min="0"
            placeholder="0,00"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
        </label>
        <label>
          {t.expenses.date}
          <input
            className="modal-field"
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
          />
        </label>
      </div>

      <div className="modal-label">{t.expenses.category}</div>
      <div className="cat-picker">
        {EXPENSE_CATEGORIES.map((c) => (
          <button
            key={c.slug}
            className={"cat-chip" + (slug === c.slug ? " active" : "")}
            style={slug === c.slug ? { borderColor: c.color, background: `${c.color}22` } : null}
            onClick={() => setSlug(slug === c.slug ? null : c.slug)}
          >
            <span>{c.icon}</span> {c.name}
          </button>
        ))}
      </div>

      <div className="modal-label">{t.expenses.notes}</div>
      <textarea
        className="modal-field"
        placeholder={t.expenses.notesPlaceholder}
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
      />

      {expense && onDelete && (
        <button className="modal-delete-btn" onClick={onDelete}>
          {t.expenses.delete}
        </button>
      )}
    </Modal>
  );
}
