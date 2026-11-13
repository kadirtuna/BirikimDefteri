// Telefondaki PortfolioCalculator'ın web karşılığı. Bakiyeler saklanmaz; her zaman işlemlerden ortalama maliyet
// yöntemiyle hesaplanır. Değerleme, bakiyenin durduğu yerin alış fiyatıyladır (bozdurunca ele geçecek tutar).

export const LIRA_ID = '00000000-0000-0000-0000-000000000001';
export const CATEGORY_TITLES = { gold: 'Altın', silver: 'Gümüş', currency: 'Döviz', fund: 'Fon', lira: 'TL', other: 'Diğer' };
export const CATEGORY_COLORS = { gold: '#D4A017', silver: '#9AA2A9', currency: '#2E7D32', fund: '#7E57C2', lira: '#D32F2F', other: '#8D6E63' };
export const KIND_TITLES = { buy: 'Alış', sell: 'Satış', transferOut: 'Aktarım', transferIn: 'Aktarım' };
export const DEBT_KIND_TITLES = { loan: 'Kredi', creditCard: 'Kredi kartı', other: 'Diğer' };
export const LOCATION_KIND_TITLES = { physical: 'Fiziki', bank: 'Banka' };
export const UNITS = ['gr', 'adet', '$', '€', '₺'];
const EPS = 1e-9;

const time = (iso) => (iso ? Date.parse(iso) : 0);
const num = (text) => (text == null || text === '' ? null : Number(text));

/// Kayıtların zaman sırası: tarih, oluşturulma zamanı, kimlik (telefondaki isChronological).
export function chronological(a, b) {
  if (a.date !== b.date) return a.date - b.date;
  if (a.createdAt !== b.createdAt) return a.createdAt - b.createdAt;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

export class Ledger {
  /// `records`: [{type, data}] — data, yedek dosyasındaki biçimdeki nesne.
  constructor(records) {
    const by = (type) => records.filter((r) => r.type === type).map((r) => r.data);
    this.people = by('person').sort((a, b) => time(a.createdAt) - time(b.createdAt));
    this.locations = by('location').sort((a, b) => time(a.createdAt) - time(b.createdAt));
    this.assets = by('asset').sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name, 'tr'));
    this.rawPrices = by('price');
    this.rawTransactions = by('transaction');
    this.debts = by('debt').sort((a, b) => time(a.updatedAt) - time(b.updatedAt));
    this.payments = by('payment').sort((a, b) => time(b.date) - time(a.date));
    this.goals = by('goal').sort((a, b) => time(a.createdAt) - time(b.createdAt));
    this.journal = by('journal').sort((a, b) => time(b.date) - time(a.date));

    this.personByID = new Map(this.people.map((x) => [x.id, x]));
    this.locationByID = new Map(this.locations.map((x) => [x.id, x]));
    this.assetByID = new Map(this.assets.map((x) => [x.id, x]));

    this.transactions = this.rawTransactions.map((t) => ({
      id: t.id, kind: t.kind, personID: t.personID, assetID: t.assetID, locationID: t.locationID,
      quantity: num(t.quantity) ?? 0, unitPrice: num(t.unitPrice) ?? 0, date: time(t.date), createdAt: time(t.createdAt),
      note: t.note || '', transferID: t.transferID || null, raw: t,
    })).sort(chronological);
    this.transactionByID = new Map(this.transactions.map((t) => [t.id, t]));

    // Fiyatlar: genel (yere bağlı olmayan) ve yere özel alış fiyatları, eskiden yeniye.
    this.generic = new Map();
    this.local = new Map();
    for (const p of this.rawPrices) {
      const point = { price: num(p.price) ?? 0, date: time(p.date) };
      const map = p.locationID ? this.local : this.generic;
      const key = p.locationID ? `${p.assetID}|${p.locationID}` : p.assetID;
      if (!map.has(key)) map.set(key, []);
      map.get(key).push(point);
    }
    for (const list of [...this.generic.values(), ...this.local.values()]) list.sort((a, b) => a.date - b.date);

    this.holdingsAll = this.replay(this.transactions);
  }

  personName(id) { return this.personByID.get(id)?.name ?? 'Bilinmeyen kişi'; }
  locationName(id) { return this.locationByID.get(id)?.name ?? 'Bilinmeyen yer'; }
  assetName(id) { return this.assetByID.get(id)?.name ?? 'Bilinmeyen ürün'; }
  unit(id) { return this.assetByID.get(id)?.unit ?? 'adet'; }
  includes(filter, personID) { return filter === 'all' || filter === personID; }

  // MARK: Fiyat

  /// Ürünün genel güncel fiyatı; TL için 1.
  price(assetID) {
    const asset = this.assetByID.get(assetID);
    if (!asset) return null;
    if (asset.unit === '₺') return 1;
    return this.generic.get(assetID)?.at(-1)?.price ?? null;
  }

  latestPrice(assetID) { return this.generic.get(assetID)?.at(-1) ?? null; }

  /// Bir yerdeki 1 birimin değeri: o yerin alış fiyatı; genel fiyat sonradan değiştiyse aradaki fark korunur.
  priceAt(assetID, locationID) {
    const asset = this.assetByID.get(assetID);
    if (!asset) return null;
    if (asset.unit === '₺') return 1;
    const general = this.generic.get(assetID) ?? [];
    const local = this.local.get(`${assetID}|${locationID}`);
    const current = general.at(-1)?.price ?? null;
    if (!local?.length) return current;
    const point = local.at(-1);
    let base = null;
    for (const g of general) if (g.date <= point.date) base = g.price;
    base ??= general[0]?.price ?? null;
    if (base == null || base <= 0 || current == null) return point.price;
    if ((general.at(-1)?.date ?? 0) <= point.date || current === base) return point.price;
    return (current * point.price) / base;
  }

  hasLocationPrice(assetID, locationID) { return this.local.has(`${assetID}|${locationID}`); }

  latestPriceDate() {
    let latest = 0;
    for (const list of [...this.generic.values(), ...this.local.values()]) latest = Math.max(latest, list.at(-1)?.date ?? 0);
    return latest || null;
  }

  // MARK: Bakiyeler

  /// İşlemleri ortalama maliyetle uygular. Aktarımın çıkış ayağı maliyeti ortalamadan düşer, giriş ayağı onu alır.
  replay(transactions, stopBefore = null) {
    const state = new Map();
    const transfers = new Map();
    for (const t of transactions) {
      if (stopBefore && !(t.id !== stopBefore.id && chronological(t, stopBefore) < 0)) continue;
      const key = `${t.personID}|${t.assetID}|${t.locationID}`;
      const pos = state.get(key) ?? { personID: t.personID, assetID: t.assetID, locationID: t.locationID, quantity: 0, cost: 0 };
      if (t.kind === 'buy') {
        pos.quantity += t.quantity;
        pos.cost += t.quantity * t.unitPrice;
      } else if (t.kind === 'transferIn') {
        pos.quantity += t.quantity;
        const carried = t.transferID ? transfers.get(t.transferID) : undefined;
        if (t.transferID) transfers.delete(t.transferID);
        pos.cost += carried ?? t.quantity * t.unitPrice;
      } else {
        const sold = Math.min(t.quantity, pos.quantity);
        let basis;
        if (sold >= pos.quantity - EPS) {
          basis = pos.cost;
          pos.quantity = 0;
          pos.cost = 0;
        } else {
          const remaining = (pos.cost * (pos.quantity - sold)) / pos.quantity;
          basis = pos.cost - remaining;
          pos.cost = remaining;
          pos.quantity -= sold;
        }
        if (t.kind === 'transferOut' && t.transferID) transfers.set(t.transferID, (transfers.get(t.transferID) ?? 0) + basis);
      }
      state.set(key, pos);
    }
    return state;
  }

  holdings(filter = 'all') {
    const result = [];
    for (const pos of this.holdingsAll.values()) {
      if (pos.quantity <= EPS || !this.includes(filter, pos.personID)) continue;
      const price = this.priceAt(pos.assetID, pos.locationID);
      result.push({ ...pos, price, value: price == null ? null : pos.quantity * price });
    }
    return result;
  }

  summary(filter = 'all') {
    const holdings = this.holdings(filter);
    const priced = holdings.filter((h) => h.price != null);
    const assets = priced.reduce((s, h) => s + h.value, 0);
    const cost = priced.reduce((s, h) => s + h.cost, 0);
    const debts = this.debtSummary(filter).total;
    const missing = new Map();
    for (const h of holdings.filter((x) => x.price == null)) missing.set(h.assetID, (missing.get(h.assetID) ?? 0) + h.quantity);
    return { assets, cost, debts, netWorth: assets - debts, profit: assets - cost, profitRatio: cost > 0 ? (assets - cost) / cost : null, missing };
  }

  /// Ürüne, türe, kişiye ya da yere göre gruplar, değere göre büyükten küçüğe.
  groups(grouping, filter = 'all') {
    const priced = this.holdings(filter).filter((h) => h.price != null);
    const total = priced.reduce((s, h) => s + h.value, 0);
    const buckets = new Map();
    for (const h of priced) {
      const key = grouping === 'asset' ? h.assetID
        : grouping === 'category' ? (this.assetByID.get(h.assetID)?.category ?? 'other')
          : grouping === 'person' ? h.personID : h.locationID;
      const g = buckets.get(key) ?? { key, quantity: 0, value: 0, cost: 0, holdings: [] };
      g.quantity += h.quantity;
      g.value += h.value;
      g.cost += h.cost;
      g.holdings.push(h);
      buckets.set(key, g);
    }
    return [...buckets.values()].map((g) => ({
      ...g,
      title: grouping === 'asset' ? this.assetName(g.key) : grouping === 'category' ? CATEGORY_TITLES[g.key] ?? 'Diğer'
        : grouping === 'person' ? this.personName(g.key) : this.locationName(g.key),
      category: grouping === 'asset' ? this.assetByID.get(g.key)?.category : grouping === 'category' ? g.key : null,
      unit: grouping === 'asset' ? this.unit(g.key) : null,
      share: total > 0 ? g.value / total : 0,
      profit: g.value - g.cost,
    })).sort((a, b) => b.value - a.value || a.title.localeCompare(b.title, 'tr'));
  }

  debtSummary(filter = 'all') {
    const debts = this.debts.filter((d) => this.includes(filter, d.personID));
    return {
      total: debts.reduce((s, d) => s + (num(d.remaining) ?? 0), 0),
      monthly: debts.reduce((s, d) => s + (num(d.monthlyInstallment) ?? 0), 0),
      debts,
    };
  }

  goalProgress(goal) {
    const filter = goal.personID ?? 'all';
    const current = goal.kind === 'quantity'
      ? this.holdings(filter).filter((h) => h.assetID === goal.assetID).reduce((s, h) => s + h.quantity, 0)
      : this.summary(filter).netWorth;
    const target = num(goal.target) ?? 0;
    return { current, target, ratio: target > 0 ? Math.min(Math.max(current / target, 0), 1) : 0 };
  }

  // MARK: Doğrulama

  /// Önerilen işlemden hemen önce aynı kişi, ürün ve yerdeki pozisyon.
  positionBefore(proposal) {
    const key = `${proposal.personID}|${proposal.assetID}|${proposal.locationID}`;
    return this.replay(this.transactions, proposal).get(key) ?? { quantity: 0, cost: 0 };
  }

  /// `removing` kimlikli işlemler çıkarılıp `adding` eklenince bir bakiye eksiye düşüyor mu? Hata mesajı ya da null.
  validateChange(removing, adding) {
    for (const p of adding) {
      if (!(p.quantity > 0)) return 'Miktar sıfırdan büyük olmalı.';
      if (p.unitPrice < 0) return 'Birim fiyat negatif olamaz.';
    }
    const keyOf = (t) => `${t.personID}|${t.assetID}|${t.locationID}`;
    const affected = new Set(adding.map(keyOf));
    for (const t of this.transactions) if (removing.has(t.id)) affected.add(keyOf(t));
    if (!affected.size) return null;
    const proposed = new Set(adding.map((p) => p.id));
    const list = [...this.transactions.filter((t) => !removing.has(t.id)), ...adding].sort(chronological);
    const balances = new Map();
    for (const t of list) {
      const key = keyOf(t);
      if (!affected.has(key)) continue;
      const balance = balances.get(key) ?? 0;
      if (t.kind === 'buy' || t.kind === 'transferIn') {
        balances.set(key, balance + t.quantity);
        continue;
      }
      if (t.quantity > balance + EPS) {
        if (!proposed.has(t.id)) return `Bu değişiklik ${new Date(t.date).toLocaleDateString('tr-TR', { day: 'numeric', month: 'short', year: 'numeric' })} tarihli satışı karşılıksız bırakıyor. Önce o satışı düzenleyin.`;
        return balance > EPS ? `Eldeki miktarı aşıyor. Bu kişi ve yerde o tarihte en fazla ${new Intl.NumberFormat('tr-TR', { maximumFractionDigits: 4 }).format(balance)} ${this.unit(t.assetID)} var.`
          : 'Bu kişi ve yerde o tarihte bu miktar yok.';
      }
      balances.set(key, balance - t.quantity);
    }
    return null;
  }

  transferLegs(transferID) {
    const legs = this.transactions.filter((t) => t.transferID === transferID);
    return { out: legs.find((t) => t.kind === 'transferOut'), in: legs.find((t) => t.kind === 'transferIn') };
  }

  isInUse(type, id) {
    if (type === 'person') return this.transactions.some((t) => t.personID === id) || this.debts.some((d) => d.personID === id);
    if (type === 'location') return this.transactions.some((t) => t.locationID === id);
    if (type === 'asset') return id === LIRA_ID || this.transactions.some((t) => t.assetID === id);
    return false;
  }
}
