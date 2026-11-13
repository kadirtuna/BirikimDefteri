// Web'deki değişiklikler. Her biri Firestore'a yazılacak kayıtları ve telefondakiyle aynı biçimde bir işlem geçmişi
// kaydını üretir; böylece geri alma ve Silinenler iki tarafta da çalışır.

import { DEBT_KIND_TITLES, KIND_TITLES } from './calc.js';
import { fmt, storageText } from './format.js';

export const newID = () => crypto.randomUUID().toUpperCase();
const iso = (d) => new Date(d).toISOString();

// İşlem geçmişindeki önce/sonra JSON'u telefonda varsayılan JSONEncoder'la yazılır: tarihler 2001'den beri saniye.
const REF = 978307200;
const DATE_FIELDS = ['date', 'createdAt', 'updatedAt', 'dueDate'];
const toRef = (entry) => {
  const copy = { ...entry };
  for (const f of DATE_FIELDS) if (copy[f] != null) copy[f] = Date.parse(copy[f]) / 1000 - REF;
  return copy;
};
const fromRef = (entry) => {
  const copy = { ...entry };
  for (const f of DATE_FIELDS) if (typeof copy[f] === 'number') copy[f] = new Date((copy[f] + REF) * 1000).toISOString();
  return copy;
};

function journal(action, entity, summary, before, after) {
  const id = newID();
  return {
    type: 'journal', id,
    data: {
      id, date: iso(Date.now()), action, entity, summary, isUndone: false,
      ...(before == null ? {} : { before: JSON.stringify(before) }),
      ...(after == null ? {} : { after: JSON.stringify(after) }),
    },
  };
}

const put = (type, data) => ({ type, id: data.id, data });
const remove = (type, id) => ({ type, id, data: null });

export function describeTrade(ledger, t) {
  const unit = ledger.unit(t.assetID);
  return `${KIND_TITLES[t.kind]} · ${ledger.assetName(t.assetID)} · ${fmt.quantity(t.quantity, unit)} · ${ledger.personName(t.personID)} · ${ledger.locationName(t.locationID)}`;
}

function describeTransfer(ledger, out, toID) {
  return `Aktarım · ${ledger.assetName(out.assetID)} · ${fmt.quantity(out.quantity, ledger.unit(out.assetID))} · ${ledger.locationName(out.locationID)} → ${ledger.locationName(toID)}`;
}

const debtName = (d) => d.institution || DEBT_KIND_TITLES[d.kind];
const describeDebt = (d) => `Borç · ${debtName(d)} · ${d.title || DEBT_KIND_TITLES[d.kind]} · ${fmt.lira(Number(d.remaining))}`;

/// Hesaplayıcının işlem biçiminden kayıt biçimine.
export function transactionEntry(t) {
  return {
    id: t.id, kind: t.kind, personID: t.personID, assetID: t.assetID, locationID: t.locationID,
    quantity: storageText(t.quantity), unitPrice: storageText(t.unitPrice), date: iso(t.date), note: t.note ?? '',
    createdAt: iso(t.createdAt), ...(t.transferID ? { transferID: t.transferID } : {}),
  };
}

// MARK: Alış, satış, aktarım

export function saveTrade(ledger, draft, existing) {
  const entry = transactionEntry(draft);
  if (existing) {
    return [put('transaction', entry), journal('edited', 'transaction', describeTrade(ledger, draft), [toRef(existing.raw)], [toRef(entry)])];
  }
  return [put('transaction', entry), journal('added', 'transaction', describeTrade(ledger, draft), [], [toRef(entry)])];
}

export function saveTransfer(ledger, legs, existingLegs) {
  const entries = legs.map(transactionEntry);
  const before = existingLegs.map((t) => toRef(t.raw));
  return [
    ...entries.map((e) => put('transaction', e)),
    journal(existingLegs.length ? 'edited' : 'added', 'transfer', describeTransfer(ledger, legs[0], legs[1].locationID), before, entries.map(toRef)),
  ];
}

/// İşlemi (aktarımsa iki ayağıyla) siler. Sonraki bir satışı bozuyorsa hata mesajı döner.
export function deleteTransaction(ledger, t) {
  const records = t.transferID ? Object.values(ledger.transferLegs(t.transferID)).filter(Boolean) : [t];
  const error = ledger.validateChange(new Set(records.map((r) => r.id)), []);
  if (error) return { error };
  const out = records.find((r) => r.kind === 'transferOut');
  const summary = t.transferID && out
    ? describeTransfer(ledger, out, records.find((r) => r.kind === 'transferIn')?.locationID)
    : describeTrade(ledger, t);
  const entry = journal('deleted', t.transferID ? 'transfer' : 'transaction', summary, records.map((r) => toRef(r.raw)), []);
  return { writes: [...records.map((r) => remove('transaction', r.id)), entry], journalID: entry.id };
}

// MARK: Borç ve ödeme

export function saveDebt(debt, existing) {
  return [put('debt', debt), journal(existing ? 'edited' : 'added', 'debt', describeDebt(debt), existing ? toRef(existing) : null, toRef(debt))];
}

export function deleteDebt(ledger, debt) {
  const payments = ledger.payments.filter((p) => p.debtID === debt.id);
  return [remove('debt', debt.id), ...payments.map((p) => remove('payment', p.id)), journal('deleted', 'debt', describeDebt(debt), toRef(debt), null)];
}

const addMonths = (isoDate, n) => {
  const d = new Date(isoDate);
  const day = d.getDate();
  d.setMonth(d.getMonth() + n, 1);
  d.setDate(Math.min(day, new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate()));
  return d.toISOString();
};

export function addPayment(debt, amount, date, note) {
  const payment = { id: newID(), debtID: debt.id, amount: storageText(amount), date: iso(date), note, createdAt: iso(Date.now()) };
  const updated = {
    ...debt,
    remaining: storageText(Math.max(Number(debt.remaining) - amount, 0)),
    ...(debt.kind === 'creditCard' && debt.dueDate ? { dueDate: addMonths(debt.dueDate, 1) } : {}),
    updatedAt: iso(Date.now()),
  };
  return [
    put('payment', payment), put('debt', updated),
    journal('added', 'payment', `Ödeme · ${debtName(debt)} · ${fmt.lira(amount)}`, { debt: toRef(debt) }, { payment: toRef(payment), debt: toRef(updated) }),
  ];
}

export function deletePayment(debt, payment) {
  const updated = { ...debt, remaining: storageText(Number(debt.remaining) + Number(payment.amount)), updatedAt: iso(Date.now()) };
  return [
    remove('payment', payment.id), put('debt', updated),
    journal('deleted', 'payment', `Ödeme · ${debtName(debt)} · ${fmt.lira(Number(payment.amount))}`,
      { payment: toRef(payment), debt: toRef(debt) }, { debt: toRef(updated) }),
  ];
}

// MARK: Fiyat ve tanımlar

export function savePrices(changes) {
  const date = iso(Date.now());
  return changes.map(({ assetID, price }) => put('price', { id: newID(), assetID, price: storageText(price), date }));
}

export const saveRecord = (type, data) => [put(type, data)];

/// Kişi, yer, ürün ya da hedefi siler; telefondaki gibi işlem geçmişine yazılır, Silinenler'den geri getirilebilir.
export function deleteDefinition(ledger, type, item) {
  const snapshot = { people: [], locations: [], assets: [], prices: [], goals: [] };
  const writes = [remove(type, item.id)];
  let summary;
  if (type === 'person') { snapshot.people.push(toRef(item)); summary = `Kişi · ${item.name}`; }
  if (type === 'location') { snapshot.locations.push(toRef(item)); summary = `Saklama yeri · ${item.name}`; }
  if (type === 'goal') { snapshot.goals.push(toRef(item)); summary = `Hedef · ${item.title}`; }
  if (type === 'asset') {
    const prices = ledger.rawPrices.filter((p) => p.assetID === item.id);
    snapshot.assets.push(toRef(item));
    snapshot.prices.push(...prices.map(toRef));
    writes.push(...prices.map((p) => remove('price', p.id)));
    summary = `Ürün · ${item.name}${prices.length ? ` · ${prices.length} fiyat kaydıyla` : ''}`;
  }
  return [...writes, journal('deleted', type, summary, snapshot, null)];
}

// MARK: Geri alma

/// İşlem geçmişindeki bir değişikliği geri alır: { writes } ya da { error }.
export function undo(ledger, entry) {
  const parse = (text) => (text ? JSON.parse(text) : null);
  const before = parse(entry.before);
  const after = parse(entry.after);
  const writes = [];

  if (entry.entity === 'transaction' || entry.entity === 'transfer') {
    const restored = (before ?? []).map(fromRef);
    const afterIDs = new Set((after ?? []).map((e) => e.id));
    const removed = [...afterIDs].filter((id) => !restored.some((r) => r.id === id));
    const proposals = restored.map((e) => ({
      ...e, quantity: Number(e.quantity), unitPrice: Number(e.unitPrice), date: Date.parse(e.date), createdAt: Date.parse(e.createdAt),
    }));
    const error = ledger.validateChange(new Set([...removed, ...restored.map((r) => r.id)]), proposals);
    if (error) return { error: `Geri alınamadı: ${error}` };
    writes.push(...removed.map((id) => remove('transaction', id)), ...restored.map((e) => put('transaction', e)));
  } else if (entry.entity === 'debt') {
    if (before) {
      writes.push(put('debt', fromRef(before)));
    } else if (after) {
      writes.push(remove('debt', after.id), ...ledger.payments.filter((p) => p.debtID === after.id).map((p) => remove('payment', p.id)));
    }
  } else if (entry.entity === 'payment') {
    if (!before?.debt) return { error: 'Bu kaydın eski hâli okunamadı.' };
    writes.push(put('debt', fromRef(before.debt)));
    if (after?.payment && !before.payment) writes.push(remove('payment', after.payment.id));
    if (before.payment && !ledger.payments.some((p) => p.id === before.payment.id)) writes.push(put('payment', fromRef(before.payment)));
  } else if (['person', 'location', 'asset', 'goal'].includes(entry.entity)) {
    const s = before ?? {};
    const missing = (type, list, existing) => (list ?? []).filter((x) => !existing.some((e) => e.id === x.id)).map((x) => put(type, fromRef(x)));
    writes.push(
      ...missing('person', s.people, ledger.people), ...missing('location', s.locations, ledger.locations),
      ...missing('asset', s.assets, ledger.assets), ...missing('price', s.prices, ledger.rawPrices), ...missing('goal', s.goals, ledger.goals),
    );
  } else {
    return { error: 'Yedekten geri yükleme yalnızca telefondan geri alınabilir.' };
  }
  writes.push(put('journal', { ...entry, isUndone: true }));
  return { writes };
}
