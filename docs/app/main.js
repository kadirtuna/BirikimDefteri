// Birikim Defteri web sürümü: telefondaki verinin aynısını gösterir ve değiştirir. Derleme adımı yoktur.

import * as act from './actions.js';
import { CATEGORY_COLORS, CATEGORY_TITLES, DEBT_KIND_TITLES, KIND_TITLES, LIRA_ID, LOCATION_KIND_TITLES, Ledger, UNITS } from './calc.js';
import { dateInput, esc, fmt, parseDecimal, startOfDay, storageText } from './format.js';
import { store } from './store.js';

const app = document.getElementById('app');
const modal = document.getElementById('modal');
const toast = document.getElementById('toast');

const saved = (() => { try { return JSON.parse(localStorage.getItem('ui') || '{}'); } catch { return {}; } })();
const ui = { tab: saved.tab || 'summary', filter: saved.filter || null, grouping: saved.grouping || 'asset', search: '', history: 'all' };
const remember = () => { try { localStorage.setItem('ui', JSON.stringify({ tab: ui.tab, filter: ui.filter, grouping: ui.grouping })); } catch { /* yok say */ } };

let ledger = null;
let meta = { fromCache: true, pending: false };
let failure = null;
let refreshModal = null;

const PALETTE = ['#1B5E3F', '#D4A017', '#1E88E5', '#D32F2F', '#8E24AA', '#00897B', '#F57C00', '#546E7A'];
const ICONS = {
  summary: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M11 2.05V11h8.95A9 9 0 1 1 11 2.05Zm2 0A9 9 0 0 1 21.95 11H13Z"/></svg>',
  records: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M4 5h2v2H4Zm4 0h12v2H8Zm-4 6h2v2H4Zm4 0h12v2H8Zm-4 6h2v2H4Zm4 0h12v2H8Z"/></svg>',
  debts: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M3 6a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v2H3Zm0 4h18v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Zm3 5v2h4v-2Z"/></svg>',
  prices: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M3 3h8l10 10-8 8L3 11Zm4.5 2.5a2 2 0 1 0 0 4 2 2 0 0 0 0-4Z"/></svg>',
  more: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M5 10a2 2 0 1 1 0 4 2 2 0 0 1 0-4Zm7 0a2 2 0 1 1 0 4 2 2 0 0 1 0-4Zm7 0a2 2 0 1 1 0 4 2 2 0 0 1 0-4Z"/></svg>',
};
const TABS = [['summary', 'Özet'], ['records', 'Kayıtlar'], ['debts', 'Borçlar'], ['prices', 'Fiyatlar'], ['more', 'Diğer']];

// MARK: Başlangıç

store.onChange = (records, m) => {
  ledger = new Ledger(records);
  meta = m;
  failure = null;
  if (!ui.filter || (ui.filter !== 'all' && !ledger.personByID.has(ui.filter))) ui.filter = ledger.people[0]?.id ?? 'all';
  render();
  refreshModal?.();
};
store.onError = (message) => { failure = message; render(); };
store.start((user) => {
  ledger = null;
  if (user) {
    app.innerHTML = '<p class="center muted" style="margin-top:40vh">Veriler yükleniyor…</p>';
  } else {
    renderLogin();
  }
});

function renderLogin() {
  app.innerHTML = `
    <div class="login">
      <img src="app/icon.png" alt="">
      <h1>Birikim Defteri</h1>
      <p class="muted">Telefondaki defterinizin web sürümü.<br>Yalnızca sahibinin Google hesabı girebilir.</p>
      <button class="btn primary" data-act="signin">Google ile giriş yap</button>
      ${failure ? `<p class="error">${esc(failure)}</p>` : ''}
    </div>`;
}

// MARK: Çizim

function render() {
  if (!store.user) return renderLogin();
  if (!ledger) return;
  const views = { summary: summaryView, records: recordsView, debts: debtsView, prices: pricesView, more: moreView, history: historyView };
  app.innerHTML = `${header()}${failure ? `<p class="error">${esc(failure)}</p>` : ''}${(views[ui.tab] ?? summaryView)()}${tabs()}`;
}

function header() {
  const status = failure ? '<span class="dot err"></span>Hata' : meta.pending ? '<span class="dot wait"></span>Gönderiliyor' : meta.fromCache ? '<span class="dot wait"></span>Çevrimdışı' : '<span class="dot"></span>Eşitlendi';
  const people = ledger.people.length > 1 ? `
    <div class="seg">${[['all', 'Herkes'], ...ledger.people.map((p) => [p.id, p.name])].map(([id, name]) =>
      `<button class="${ui.filter === id ? 'on' : ''}" data-act="filter" data-id="${esc(id)}">${esc(name)}</button>`).join('')}</div>` : '';
  const showsFilter = ['summary', 'debts'].includes(ui.tab);
  return `<header class="top"><div class="title"><img src="app/icon.png" alt="">Birikim Defteri</div><div class="sync">${status}</div></header>
    ${showsFilter ? people : ''}`;
}

function tabs() {
  const current = ui.tab === 'history' ? 'more' : ui.tab;
  return `<nav class="tabs"><div class="inner">${TABS.map(([id, title]) =>
    `<button class="${current === id ? 'on' : ''}" data-act="tab" data-id="${id}">${ICONS[id]}${title}</button>`).join('')}</div></nav>`;
}

function avatar(text, color, size = 36) {
  const initials = String(text).replace(/[^\p{L}\p{N}\s]/gu, ' ').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toLocaleUpperCase('tr');
  return `<span class="avatar" style="background:${color};width:${size}px;height:${size}px">${esc(initials)}</span>`;
}

const assetColor = (id) => CATEGORY_COLORS[ledger.assetByID.get(id)?.category] ?? '#8D6E63';
const indexColor = (list, id) => PALETTE[Math.max(list.findIndex((x) => x.id === id), 0) % PALETTE.length];
const locationColor = (id) => (ledger.locationByID.get(id)?.kind === 'physical' ? '#2E7D32' : indexColor(ledger.locations, id));
const signed = (v) => `<span class="${v >= 0 ? 'pos' : 'neg'}">${fmt.signedLira(v)}</span>`;

// MARK: Özet

function summaryView() {
  const s = ledger.summary(ui.filter);
  const groups = ledger.groups(ui.grouping, ui.filter);
  const priceDate = ledger.latestPriceDate();
  const goals = ledger.goals.filter((g) => !g.personID || ui.filter === 'all' || g.personID === ui.filter);
  const colorOf = (g) => (ui.grouping === 'asset' || ui.grouping === 'category') ? CATEGORY_COLORS[g.category] ?? '#8D6E63'
    : ui.grouping === 'person' ? indexColor(ledger.people, g.key) : locationColor(g.key);
  return `
    <section class="hero">
      <div class="label">Net varlık</div>
      <div class="big num">${fmt.lira(s.netWorth)}</div>
      <div class="small" style="opacity:.75">${priceDate ? `Fiyatlar ${fmt.dateTime(priceDate)} · telefondan` : 'Henüz fiyat yok'}</div>
      <div class="metrics num">
        <div><span>Varlıklar</span><b>${fmt.lira(s.assets)}</b></div>
        <div><span>Borçlar</span><b>${fmt.lira(s.debts)}</b></div>
        <div><span>Kâr/Zarar</span><b>${fmt.signedLira(s.profit)}</b>${s.profitRatio != null ? `<span>${fmt.signedPercent(s.profitRatio)}</span>` : ''}</div>
      </div>
    </section>
    <div class="seg">${[['asset', 'Ürün'], ['category', 'Tür'], ['person', 'Kişi'], ['location', 'Yer']].map(([id, t]) =>
      `<button class="${ui.grouping === id ? 'on' : ''}" data-act="grouping" data-id="${id}">${t}</button>`).join('')}</div>
    <h2>Değerler, varlığın durduğu yerin alış fiyatıyladır (bozdurunca ele geçecek tutar).</h2>
    <div class="card">${groups.map((g) => `
      <div class="row">
        ${avatar(g.title, colorOf(g))}
        <div class="grow">
          <div style="display:flex;justify-content:space-between;gap:8px"><span class="title">${esc(g.title)}</span><b class="num">${fmt.lira(g.value)}</b></div>
          <div class="sub" style="display:flex;justify-content:space-between;gap:8px">
            <span class="num">${g.unit ? fmt.quantity(g.quantity, g.unit) : signed(g.profit)}</span><span class="num">${fmt.percent(g.share)}</span>
          </div>
          <div class="bar"><i style="width:${(g.share * 100).toFixed(1)}%;background:${colorOf(g)}"></i></div>
        </div>
      </div>`).join('') || '<p class="muted center">Henüz varlık yok.</p>'}</div>
    ${s.missing.size ? `<h2>Fiyatı girilmemiş (toplamlara katılmadı)</h2><div class="card">${[...s.missing].map(([id, q]) =>
      `<div class="row"><div class="grow">${esc(ledger.assetName(id))}</div><div class="num">${fmt.quantity(q, ledger.unit(id))}</div></div>`).join('')}</div>` : ''}
    ${goals.length ? `<h2>Hedefler</h2><div class="card">${goals.map((g) => {
      const p = ledger.goalProgress(g);
      const amount = (v) => (g.kind === 'quantity' ? fmt.quantity(v, ledger.unit(g.assetID)) : fmt.lira(v));
      return `<div class="row"><div class="grow"><div style="display:flex;justify-content:space-between"><span>${esc(g.title)}</span><b>${fmt.percent(p.ratio)}</b></div>
        <div class="bar"><i style="width:${(p.ratio * 100).toFixed(1)}%;background:var(--gold)"></i></div>
        <div class="sub num">${amount(p.current)} / ${amount(p.target)}</div></div></div>`;
    }).join('')}</div>` : ''}`;
}

// MARK: Kayıtlar

function recordsView() {
  return `
    <h1>Kayıtlar</h1>
    <div class="actions">
      <button class="btn gold" data-act="new-trade">+ Alış / Satış</button>
      <button class="btn" data-act="new-transfer">⇄ Aktarım</button>
    </div>
    <input class="search" type="search" placeholder="Ürün, yer, kişi ya da not" value="${esc(ui.search)}" data-input="search">
    <div id="list">${recordList()}</div>`;
}

function recordList() {
  const q = ui.search.trim().toLocaleLowerCase('tr');
  const seen = new Set();
  const rows = [...ledger.transactions].reverse().filter((t) => {
    if (t.transferID) {
      if (seen.has(t.transferID)) return false;
      seen.add(t.transferID);
    }
    if (!q) return true;
    const legs = t.transferID ? Object.values(ledger.transferLegs(t.transferID)).filter(Boolean) : [t];
    return [ledger.assetName(t.assetID), ledger.personName(t.personID), KIND_TITLES[t.kind], t.note, ...legs.map((l) => ledger.locationName(l.locationID))]
      .some((x) => String(x).toLocaleLowerCase('tr').includes(q));
  });
  const months = new Map();
  for (const t of rows) {
    const d = new Date(t.date);
    const key = `${d.getFullYear()}-${d.getMonth()}`;
    if (!months.has(key)) months.set(key, { date: new Date(d.getFullYear(), d.getMonth(), 1), rows: [] });
    months.get(key).rows.push(t);
  }
  if (!months.size) return `<p class="muted center">${q ? 'Eşleşen kayıt yok.' : 'Henüz kayıt yok.'}</p>`;
  return [...months.values()].map((m) => {
    const trades = m.rows.filter((t) => !t.transferID);
    const bought = trades.filter((t) => t.kind === 'buy').reduce((s, t) => s + t.quantity * t.unitPrice, 0);
    const sold = trades.filter((t) => t.kind === 'sell').reduce((s, t) => s + t.quantity * t.unitPrice, 0);
    const totals = [bought ? `Alım ${fmt.lira(bought)}` : '', sold ? `Satış ${fmt.lira(sold)}` : ''].filter(Boolean).join(' · ');
    return `<h2 style="display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap"><span>${fmt.month(m.date)}</span><span class="num">${totals}</span></h2>
      <div class="card">${m.rows.map(recordRow).join('')}</div>`;
  }).join('');
}

function recordRow(t) {
  const unit = ledger.unit(t.assetID);
  let sub;
  let right;
  if (t.transferID) {
    const legs = ledger.transferLegs(t.transferID);
    sub = `Aktarım · ${ledger.personName(t.personID)} · ${ledger.locationName(legs.out?.locationID)} → ${ledger.locationName(legs.in?.locationID)}`;
    right = `<div class="num">${fmt.quantity(t.quantity, unit)}</div>`;
  } else {
    sub = `${KIND_TITLES[t.kind]} · ${ledger.personName(t.personID)} · ${ledger.locationName(t.locationID)}`;
    const sign = t.kind === 'buy' ? '+' : '−';
    right = `<div class="num ${t.kind === 'buy' ? 'pos' : 'neg'}">${sign}${fmt.quantity(t.quantity, unit)}</div><div class="num">${fmt.lira(t.quantity * t.unitPrice)}</div>`;
  }
  return `<div class="row tap" data-act="open-record" data-id="${t.id}">
    ${avatar(ledger.assetName(t.assetID), assetColor(t.assetID))}
    <div class="grow"><div class="title">${esc(ledger.assetName(t.assetID))}</div><div class="sub">${esc(sub)}</div>
      ${t.note ? `<div class="sub">${esc(t.note)}</div>` : ''}</div>
    <div class="right">${right}<div class="sub">${fmt.date(t.date)}</div></div>
  </div>`;
}

// MARK: Borçlar

function debtsView() {
  const summary = ledger.debtSummary(ui.filter);
  const groups = new Map();
  for (const d of summary.debts) {
    const key = d.institution || 'Kurum belirtilmemiş';
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(d);
  }
  return `
    <section class="hero debt">
      <div class="label" style="color:#FFCDB8">Toplam borç</div>
      <div class="big num">${fmt.lira(summary.total)}</div>
      <div class="small num" style="opacity:.85">Aylık taksit: ${fmt.lira(summary.monthly)}</div>
    </section>
    <div class="actions"><button class="btn gold" data-act="new-debt">+ Borç ekle</button></div>
    ${[...groups].sort(([a], [b]) => a.localeCompare(b, 'tr')).map(([name, debts]) => `
      <h2>${esc(name)}</h2><div class="card">${debts.map((d) => `
        <div class="row tap" data-act="open-debt" data-id="${d.id}">
          ${avatar(d.institution || DEBT_KIND_TITLES[d.kind], d.kind === 'creditCard' ? '#8E24AA' : d.kind === 'loan' ? '#1E88E5' : '#607D8B')}
          <div class="grow"><div class="title">${esc(d.title || DEBT_KIND_TITLES[d.kind])}</div>
            <div class="sub">${esc([DEBT_KIND_TITLES[d.kind], d.monthlyInstallment ? `Aylık ${fmt.lira(Number(d.monthlyInstallment))}` : '',
              d.dueDate ? `${d.kind === 'creditCard' ? 'Son ödeme' : 'Bitiş'} ${fmt.date(d.dueDate)}` : '',
              ledger.people.length > 1 ? ledger.personName(d.personID) : ''].filter(Boolean).join(' · '))}</div></div>
          <div class="right num">${fmt.lira(Number(d.remaining))}</div>
        </div>`).join('')}</div>`).join('') || '<p class="muted center">Borç kaydı yok.</p>'}`;
}

// MARK: Fiyatlar

function pricesView() {
  const held = ledger.holdings('all');
  return `
    <h1>Fiyatlar</h1>
    <p class="muted small">İnternetten fiyatları telefon çeker ve buraya eşitler (altın ve gümüş: Kapalıçarşı alışı, dolar ve euro: TCMB, kurumların alışı: doviz.com). Burada elle fiyat girebilirsiniz; 1 birimin TL karşılığını yazın.</p>
    <form id="prices"><div class="card">${ledger.assets.filter((a) => a.unit !== '₺').map((a) => {
      const latest = ledger.latestPrice(a.id);
      const places = [...new Set(held.filter((h) => h.assetID === a.id && ledger.hasLocationPrice(a.id, h.locationID)).map((h) => h.locationID))];
      return `<div class="row">
        ${avatar(a.name, assetColor(a.id))}
        <div class="grow"><div class="title">${esc(a.name)}</div>
          <div class="sub">1 ${esc(a.unit)} · ${latest ? fmt.dateTime(latest.date) : '<span style="color:var(--gold)">Fiyat girilmedi</span>'}</div>
          ${places.map((id) => `<div class="sub" style="color:var(--green-2)">${esc(ledger.locationName(id))} alışı ${fmt.lira(ledger.priceAt(a.id, id))}</div>`).join('')}
        </div>
        <input class="num" style="width:120px;text-align:right;border:1px solid var(--line);border-radius:9px;padding:8px;background:var(--card)"
          inputmode="decimal" name="${a.id}" placeholder="₺0,00" value="${latest ? fmt.editable(latest.price) : ''}" data-original="${latest ? fmt.editable(latest.price) : ''}">
      </div>`;
    }).join('')}</div>
    <div class="error" id="price-error"></div>
    <button class="btn primary" type="submit">Değişen fiyatları kaydet</button></form>`;
}

// MARK: Diğer

function moreView() {
  const list = (type, items, label, sub) => `<div class="card">${items.map((x) => `
    <div class="row tap" data-act="edit-def" data-type="${type}" data-id="${x.id}"><div class="grow"><div class="title">${esc(label(x))}</div>${sub ? `<div class="sub">${esc(sub(x))}</div>` : ''}</div><span class="muted">›</span></div>`).join('')}
    <div class="row tap" data-act="new-def" data-type="${type}"><div class="grow" style="color:var(--green-2);font-weight:600">+ Ekle</div></div></div>`;
  return `
    <h1>Diğer</h1>
    <div class="card"><div class="row tap" data-act="tab" data-id="history"><div class="grow"><div class="title">İşlem geçmişi ve Silinenler</div><div class="sub">Her değişikliği geri alın, silinenleri geri getirin</div></div><span class="muted">›</span></div></div>
    <h2>Kişiler</h2>${list('person', ledger.people, (x) => x.name)}
    <h2>Saklama yerleri</h2>${list('location', ledger.locations, (x) => x.name, (x) => LOCATION_KIND_TITLES[x.kind])}
    <h2>Ürünler</h2>${list('asset', ledger.assets, (x) => x.name, (x) => `${x.unit} · ${CATEGORY_TITLES[x.category] ?? ''}`)}
    <h2>Hedefler</h2>${list('goal', ledger.goals, (x) => x.title, (x) => (x.kind === 'quantity' ? fmt.quantity(Number(x.target), ledger.unit(x.assetID)) : fmt.lira(Number(x.target))))}
    <h2>Hesap</h2><div class="card"><div class="row"><div class="grow">${esc(store.user?.email ?? '')}</div><button class="btn danger" data-act="signout">Çıkış yap</button></div></div>
    <p class="muted small center">Telefon uygulaması bu verilerle dakikada bir eşitlenir.</p>`;
}

function historyView() {
  const entries = ledger.journal.filter((e) => ui.history === 'all' || e.action === 'deleted' || e.action === 'restored');
  const days = new Map();
  for (const e of entries) {
    const key = fmt.date(e.date);
    if (!days.has(key)) days.set(key, []);
    days.get(key).push(e);
  }
  const titles = { added: 'Eklendi', edited: 'Düzenlendi', deleted: 'Silindi', restored: 'Yedekten geri yüklendi' };
  return `
    <h1>İşlem geçmişi</h1>
    <div class="seg"><button class="${ui.history === 'all' ? 'on' : ''}" data-act="history" data-id="all">Tümü</button>
      <button class="${ui.history === 'deleted' ? 'on' : ''}" data-act="history" data-id="deleted">Silinenler</button></div>
    ${ui.history === 'deleted' ? '<p class="muted small">Silinen kayıtlar burada hep kalır; istediğiniz zaman geri getirebilirsiniz.</p>' : ''}
    ${[...days].map(([day, list]) => `<h2>${day}</h2><div class="card">${list.map((e) => `
      <div class="row"><div class="grow"><div class="${e.isUndone ? 'strike' : ''}">${esc(e.summary)}</div>
        <div class="sub">${titles[e.action] ?? ''} · ${new Date(e.date).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })}${e.isUndone ? ' · geri alındı' : ''}</div></div>
        ${e.isUndone || e.entity === 'backup' ? '' : `<button class="btn small" data-act="undo" data-id="${e.id}">${e.action === 'deleted' ? 'Geri getir' : 'Geri al'}</button>`}
      </div>`).join('')}</div>`).join('') || '<p class="muted center">Kayıt yok.</p>'}`;
}

// MARK: Formlar

function openModal(html, { onInput, onSubmit, onClick } = {}) {
  modal.innerHTML = html;
  const form = modal.querySelector('form');
  refreshModal = onInput ? () => onInput(form) : null;
  form?.addEventListener('input', () => onInput?.(form));
  form?.addEventListener('change', () => onInput?.(form));
  form?.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (event.submitter?.value === 'cancel') return closeModal();
    await onSubmit?.(form, event.submitter?.value);
  });
  modal.onclick = (event) => onClick?.(event);
  if (!modal.open) modal.showModal();
  onInput?.(form);
}

function closeModal() {
  refreshModal = null;
  modal.close();
}

const options = (items, selected, label = (x) => x.name, value = (x) => x.id) =>
  items.map((x) => `<option value="${esc(value(x))}" ${value(x) === selected ? 'selected' : ''}>${esc(label(x))}</option>`).join('');
const formHead = (title) => `<div class="head"><b>${title}</b><button class="btn small" value="cancel" formnovalidate>Vazgeç</button></div>`;

async function commit(writes, success) {
  try {
    await store.commit(writes);
    success?.();
  } catch (error) {
    alert(`Kaydedilemedi: ${error.message}`);
  }
}

function openTrade(existing) {
  const draftID = existing?.id ?? act.newID();
  const createdAt = existing?.createdAt ?? Date.now();
  const last = (() => { try { return JSON.parse(localStorage.getItem('last') || '{}'); } catch { return {}; } })();
  const v = existing ?? { kind: 'buy', personID: last.personID ?? ledger.people[0]?.id, locationID: last.locationID ?? ledger.locations[0]?.id, date: startOfDay(Date.now()).getTime() };
  const draft = (form) => {
    const asset = ledger.assetByID.get(form.assetID.value);
    const isLira = asset?.unit === '₺';
    const quantity = parseDecimal(form.quantity.value);
    const priceText = form.unitPrice.value.trim();
    const unitPrice = isLira ? 1 : priceText ? parseDecimal(priceText) : ledger.price(form.assetID.value);
    return {
      asset, isLira, quantity, unitPrice, priceText,
      tx: { id: draftID, kind: form.kind.value, personID: form.personID.value, assetID: form.assetID.value, locationID: form.locationID.value,
        quantity: quantity ?? 0, unitPrice: unitPrice ?? 0, date: startOfDay(dateInput.parse(form.date.value)).getTime(), createdAt,
        note: form.note.value.trim(), transferID: null },
    };
  };
  const problem = (form) => {
    const d = draft(form);
    if (!d.asset) return 'Ürün seçin.';
    if (form.quantity.value.trim() && d.quantity == null) return 'Miktar geçerli bir sayı değil.';
    if (!d.isLira && d.priceText && d.unitPrice == null) return 'Birim fiyat geçerli bir sayı değil.';
    if (!d.isLira && !d.priceText && d.unitPrice == null) return 'Bu ürünün güncel fiyatı yok; birim fiyatı girin.';
    if (d.quantity == null) return '';
    return ledger.validateChange(new Set([draftID]), [d.tx]) ?? '';
  };
  openModal(`<form>${formHead(existing ? 'İşlemi düzenle' : 'Yeni işlem')}
    <div class="seg"><label style="flex:1"><input type="radio" name="kind" value="buy" ${v.kind === 'buy' ? 'checked' : ''} hidden><span class="btn small" style="display:block;text-align:center">Alış</span></label>
      <label style="flex:1"><input type="radio" name="kind" value="sell" ${v.kind === 'sell' ? 'checked' : ''} hidden><span class="btn small" style="display:block;text-align:center">Satış</span></label></div>
    <label class="field"><span>Ürün</span><select name="assetID">${existing ? '' : '<option value="">Seçin</option>'}${options(ledger.assets, v.assetID)}</select></label>
    <div class="grid2"><label class="field"><span>Kişi</span><select name="personID">${options(ledger.people, v.personID)}</select></label>
      <label class="field"><span>Yer</span><select name="locationID">${options(ledger.locations, v.locationID)}</select></label></div>
    <div class="grid2"><label class="field"><span>Miktar</span><input name="quantity" inputmode="decimal" value="${existing ? fmt.editable(existing.quantity) : ''}" placeholder="0"></label>
      <label class="field" id="price-field"><span>Birim fiyat (₺)</span><input name="unitPrice" inputmode="decimal" value="${existing && existing.assetID !== LIRA_ID ? fmt.editable(existing.unitPrice) : ''}"></label></div>
    <div class="grid2"><label class="field"><span>Tarih</span><input type="date" name="date" value="${dateInput.value(v.date)}"></label>
      <label class="field"><span>Not</span><input name="note" value="${esc(existing?.note ?? '')}"></label></div>
    <div class="muted small" id="hint"></div>
    <div class="total num" id="total">—</div>
    <div class="error" id="problem"></div>
    <div class="actions"><button class="btn primary" value="save">Kaydet</button>${existing ? '<button class="btn danger" value="delete" formnovalidate>İşlemi sil</button>' : ''}</div>
  </form>`, {
    onInput(form) {
      const d = draft(form);
      form.querySelectorAll('.seg span').forEach((s) => { s.style.background = s.previousElementSibling.checked ? 'var(--card)' : 'transparent'; });
      form.querySelector('#price-field').hidden = d.isLira;
      form.unitPrice.placeholder = d.asset && !d.isLira && ledger.price(d.asset.id) != null ? `${fmt.lira(ledger.price(d.asset.id))} (güncel)` : '₺0,00';
      form.querySelector('#total').textContent = d.quantity != null && d.unitPrice != null ? fmt.lira(d.quantity * d.unitPrice) : '—';
      const available = d.asset && form.kind.value === 'sell' ? ledger.positionBefore(d.tx).quantity : null;
      form.querySelector('#hint').textContent = available != null ? `Bu kişi ve yerde mevcut: ${fmt.quantity(Math.max(available, 0), d.asset.unit)}` : '';
      const text = problem(form);
      form.querySelector('#problem').textContent = text;
      form.querySelector('[value=save]').disabled = Boolean(text) || d.quantity == null;
    },
    async onSubmit(form, action) {
      if (action === 'delete') return removeTransaction(existing);
      if (problem(form)) return;
      const d = draft(form);
      try { localStorage.setItem('last', JSON.stringify({ personID: d.tx.personID, locationID: d.tx.locationID })); } catch { /* yok say */ }
      await commit(act.saveTrade(ledger, d.tx, existing), closeModal);
    },
  });
}

function openTransfer(transferID) {
  const legs = transferID ? ledger.transferLegs(transferID) : {};
  const out = legs.out;
  const ids = { out: out?.id ?? act.newID(), in: legs.in?.id ?? act.newID(), transfer: transferID ?? act.newID(), createdAt: out?.createdAt ?? Date.now() };
  const build = (form) => {
    const quantity = parseDecimal(form.quantity.value);
    const base = { personID: form.personID.value, assetID: form.assetID.value, quantity: quantity ?? 0,
      date: startOfDay(dateInput.parse(form.date.value)).getTime(), note: form.note.value.trim(), transferID: ids.transfer };
    const outLeg = { ...base, id: ids.out, kind: 'transferOut', locationID: form.fromID.value, createdAt: ids.createdAt, unitPrice: 0 };
    const before = ledger.positionBefore(outLeg);
    outLeg.unitPrice = before.quantity > 0 ? before.cost / before.quantity : 0;
    const inLeg = { ...outLeg, id: ids.in, kind: 'transferIn', locationID: form.toID.value, createdAt: ids.createdAt + 1 };
    return { quantity, legs: [outLeg, inLeg], available: before.quantity };
  };
  const problem = (form) => {
    const b = build(form);
    if (!form.assetID.value) return 'Ürün seçin.';
    if (form.fromID.value === form.toID.value) return 'Nereden ve nereye aynı yer olamaz.';
    if (form.quantity.value.trim() && b.quantity == null) return 'Miktar geçerli bir sayı değil.';
    if (b.quantity == null) return '';
    return ledger.validateChange(new Set([ids.out, ids.in]), b.legs) ?? '';
  };
  const first = ledger.locations[0]?.id;
  openModal(`<form>${formHead(transferID ? 'Aktarım' : 'Yeni aktarım')}
    <p class="muted small">Aktarım kâr ya da zarar doğurmaz; ürün ortalama maliyetiyle birlikte taşınır.</p>
    <label class="field"><span>Ürün</span><select name="assetID">${out ? '' : '<option value="">Seçin</option>'}${options(ledger.assets, out?.assetID)}</select></label>
    <label class="field"><span>Kişi</span><select name="personID">${options(ledger.people, out?.personID ?? ledger.people[0]?.id)}</select></label>
    <div class="grid2"><label class="field"><span>Nereden</span><select name="fromID">${options(ledger.locations, out?.locationID ?? first)}</select></label>
      <label class="field"><span>Nereye</span><select name="toID">${options(ledger.locations, legs.in?.locationID ?? ledger.locations[1]?.id)}</select></label></div>
    <div class="grid2"><label class="field"><span>Miktar</span><input name="quantity" inputmode="decimal" value="${out ? fmt.editable(out.quantity) : ''}"></label>
      <label class="field"><span>Tarih</span><input type="date" name="date" value="${dateInput.value(out?.date ?? Date.now())}"></label></div>
    <label class="field"><span>Not</span><input name="note" value="${esc(out?.note ?? '')}"></label>
    <div class="muted small" id="hint"></div>
    <div class="error" id="problem"></div>
    <div class="actions"><button class="btn primary" value="save">Kaydet</button><button class="btn" value="all" formnovalidate>Tümünü aktar</button>
      ${out ? '<button class="btn danger" value="delete" formnovalidate>Aktarımı sil</button>' : ''}</div>
  </form>`, {
    onInput(form) {
      const b = build(form);
      const unit = ledger.unit(form.assetID.value);
      form.querySelector('#hint').textContent = form.assetID.value ? `Bu kişi ve yerde mevcut: ${fmt.quantity(Math.max(b.available, 0), unit)}` : '';
      const text = problem(form);
      form.querySelector('#problem').textContent = text;
      form.querySelector('[value=save]').disabled = Boolean(text) || b.quantity == null;
    },
    async onSubmit(form, action) {
      if (action === 'delete') return removeTransaction(out);
      if (action === 'all') {
        form.quantity.value = fmt.editable(Math.max(build(form).available, 0));
        return refreshModal?.();
      }
      if (problem(form)) return;
      await commit(act.saveTransfer(ledger, build(form).legs, [legs.out, legs.in].filter(Boolean)), closeModal);
    },
  });
}

async function removeTransaction(t) {
  if (!confirm('Bu işlem silinsin mi? İşlem geçmişinden geri getirebilirsiniz.')) return;
  const result = act.deleteTransaction(ledger, t);
  if (result.error) return alert(result.error);
  await commit(result.writes, () => {
    closeModal();
    showUndo('Kayıt silindi', result.journalID);
  });
}

function showUndo(message, journalID) {
  toast.innerHTML = `<span>${esc(message)}</span><button class="btn small" data-act="undo" data-id="${journalID}">Geri al</button>`;
  toast.hidden = false;
  clearTimeout(showUndo.timer);
  showUndo.timer = setTimeout(() => { toast.hidden = true; }, 6000);
}

function openDebt(id) {
  const debt = ledger.debts.find((d) => d.id === id);
  if (!debt) return closeModal();
  const payments = ledger.payments.filter((p) => p.debtID === id);
  const remaining = Number(debt.remaining);
  const monthly = Number(debt.monthlyInstallment || 0);
  const months = monthly > 0 && remaining > 0 ? Math.ceil(remaining / monthly) : null;
  const paid = payments.reduce((s, p) => s + Number(p.amount), 0);
  openModal(`<form>${formHead(esc(debt.institution || 'Borç'))}
    <div class="card">
      <div class="row"><div class="grow"><b>${esc(debt.title || DEBT_KIND_TITLES[debt.kind])}</b><div class="sub">${DEBT_KIND_TITLES[debt.kind]} · ${esc(ledger.personName(debt.personID))}</div></div><b class="num">${fmt.lira(remaining)}</b></div>
      ${monthly ? `<div class="row"><div class="grow">Aylık taksit</div><div class="num">${fmt.lira(monthly)}</div></div>` : ''}
      ${debt.paymentDay ? `<div class="row"><div class="grow">Taksit günü</div><div>Her ayın ${debt.paymentDay}'i</div></div>` : ''}
      ${debt.dueDate ? `<div class="row"><div class="grow">${debt.kind === 'creditCard' ? 'Son ödeme' : 'Bitiş tarihi'}</div><div>${fmt.date(debt.dueDate)}</div></div>` : ''}
      ${months ? `<div class="row"><div class="grow">Tahmini bitiş</div><div>${months} taksit</div></div>` : ''}
      ${paid ? `<div class="row"><div class="grow">Toplam ödenen</div><div class="num">${fmt.lira(paid)}</div></div>` : ''}
    </div>
    <h2>Ödeme ekle</h2>
    <div class="grid2"><label class="field"><span>Tutar (₺)</span><input name="amount" inputmode="decimal" value="${monthly ? fmt.editable(Math.min(monthly, remaining)) : ''}"></label>
      <label class="field"><span>Tarih</span><input type="date" name="date" value="${dateInput.value(Date.now())}"></label></div>
    <label class="field"><span>Not</span><input name="note"></label>
    <div class="error" id="problem"></div>
    <div class="actions"><button class="btn primary" value="pay">Ödemeyi kaydet</button><button class="btn" value="edit" formnovalidate>Borcu düzenle</button>
      <button class="btn danger" value="delete" formnovalidate>Borcu sil</button></div>
    ${payments.length ? `<h2>Ödeme geçmişi</h2><div class="card">${payments.map((p) => `
      <div class="row"><div class="grow"><div class="num">${fmt.lira(Number(p.amount))}</div><div class="sub">${fmt.date(p.date)}${p.note ? ` · ${esc(p.note)}` : ''}</div></div>
        <button class="btn small danger" type="button" data-payment="${p.id}">Sil</button></div>`).join('')}</div>` : ''}
  </form>`, {
    onInput(form) {
      const amount = parseDecimal(form.amount.value);
      const text = !form.amount.value.trim() ? '' : !(amount > 0) ? 'Tutar sıfırdan büyük bir sayı olmalı.'
        : amount > remaining + 1e-9 ? `Tutar kalan borçtan (${fmt.lira(remaining)}) fazla olamaz.` : '';
      form.querySelector('#problem').textContent = text;
      form.querySelector('[value=pay]').disabled = Boolean(text) || amount == null;
    },
    async onSubmit(form, action) {
      if (action === 'edit') return openDebtForm(debt);
      if (action === 'delete') {
        if (!confirm('Bu borç ve ödeme geçmişi silinsin mi? İşlem geçmişinden geri getirebilirsiniz.')) return;
        return commit(act.deleteDebt(ledger, debt), closeModal);
      }
      const amount = parseDecimal(form.amount.value);
      if (!(amount > 0) || amount > remaining + 1e-9) return;
      await commit(act.addPayment(debt, amount, startOfDay(dateInput.parse(form.date.value)), form.note.value.trim()), closeModal);
    },
    async onClick(event) {
      const id = event.target.closest('[data-payment]')?.dataset.payment;
      if (!id || !confirm('Bu ödeme silinsin mi? Tutar kalan borca geri eklenir.')) return;
      await commit(act.deletePayment(debt, payments.find((p) => p.id === id)), closeModal);
    },
  });
}

function openDebtForm(existing) {
  const d = existing ?? { kind: 'loan', personID: ledger.people[0]?.id };
  openModal(`<form>${formHead(existing ? 'Borcu düzenle' : 'Yeni borç')}
    <label class="field"><span>Tür</span><select name="kind">${Object.entries(DEBT_KIND_TITLES).map(([k, t]) => `<option value="${k}" ${d.kind === k ? 'selected' : ''}>${t}</option>`).join('')}</select></label>
    <div class="grid2"><label class="field"><span>Kurum</span><input name="institution" value="${esc(d.institution ?? '')}" placeholder="ör. Ziraat Bankası"></label>
      <label class="field"><span>Açıklama</span><input name="title" value="${esc(d.title ?? '')}" placeholder="ör. İhtiyaç kredisi"></label></div>
    <label class="field"><span>Kişi</span><select name="personID">${options(ledger.people, d.personID)}</select></label>
    <div class="grid2"><label class="field"><span>Kalan borç (₺)</span><input name="remaining" inputmode="decimal" value="${d.remaining ? fmt.editable(Number(d.remaining)) : ''}" required></label>
      <label class="field"><span>Aylık taksit (₺)</span><input name="monthly" inputmode="decimal" value="${d.monthlyInstallment ? fmt.editable(Number(d.monthlyInstallment)) : ''}"></label></div>
    <div class="grid2"><label class="field"><span>Son ödeme / bitiş</span><input type="date" name="dueDate" value="${d.dueDate ? dateInput.value(d.dueDate) : ''}"></label>
      <label class="field"><span>Taksit günü</span><select name="paymentDay"><option value="">Yok</option>${Array.from({ length: 28 }, (_, i) =>
        `<option value="${i + 1}" ${d.paymentDay === i + 1 ? 'selected' : ''}>${i + 1}</option>`).join('')}</select></label></div>
    <label class="field"><span>Not</span><input name="note" value="${esc(d.note ?? '')}"></label>
    <div class="error" id="problem"></div>
    <div class="actions"><button class="btn primary" value="save">Kaydet</button></div>
  </form>`, {
    onInput(form) {
      const remaining = parseDecimal(form.remaining.value);
      const monthly = form.monthly.value.trim() ? parseDecimal(form.monthly.value) : 0;
      const text = form.remaining.value.trim() && (remaining == null || remaining < 0) ? 'Kalan borç geçerli bir sayı değil.'
        : monthly == null ? 'Aylık taksit geçerli bir sayı değil.' : '';
      form.querySelector('#problem').textContent = text;
      form.querySelector('[value=save]').disabled = Boolean(text) || remaining == null;
    },
    async onSubmit(form) {
      const monthly = form.monthly.value.trim() ? parseDecimal(form.monthly.value) : null;
      const debt = {
        id: existing?.id ?? act.newID(), personID: form.personID.value, institution: form.institution.value.trim(), kind: form.kind.value,
        title: form.title.value.trim(), remaining: storageText(parseDecimal(form.remaining.value)), note: form.note.value.trim(),
        updatedAt: new Date().toISOString(),
        ...(monthly ? { monthlyInstallment: storageText(monthly) } : {}),
        ...(form.dueDate.value ? { dueDate: dateInput.parse(form.dueDate.value).toISOString() } : {}),
        ...(form.paymentDay.value ? { paymentDay: Number(form.paymentDay.value) } : {}),
      };
      await commit(act.saveDebt(debt, existing), closeModal);
    },
  });
}

function openDefinition(type, existing) {
  const titles = { person: 'Kişi', location: 'Saklama yeri', asset: 'Ürün', goal: 'Hedef' };
  const x = existing ?? {};
  const inUse = existing && ledger.isInUse(type, existing.id);
  const fields = {
    person: `<label class="field"><span>Ad</span><input name="name" value="${esc(x.name ?? '')}" required></label>`,
    location: `<label class="field"><span>Ad</span><input name="name" value="${esc(x.name ?? '')}" placeholder="ör. Ziraat Bankası, Kasa" required></label>
      <label class="field"><span>Tür</span><select name="kind">${Object.entries(LOCATION_KIND_TITLES).map(([k, t]) => `<option value="${k}" ${(x.kind ?? 'bank') === k ? 'selected' : ''}>${t}</option>`).join('')}</select></label>`,
    asset: `<label class="field"><span>Ad</span><input name="name" value="${esc(x.name ?? '')}" required></label>
      <div class="grid2"><label class="field"><span>Birim</span><select name="unit" ${inUse ? 'disabled' : ''}>${UNITS.map((u) => `<option ${(x.unit ?? 'gr') === u ? 'selected' : ''}>${u}</option>`).join('')}</select></label>
      <label class="field"><span>Tür</span><select name="category">${Object.entries(CATEGORY_TITLES).map(([k, t]) => `<option value="${k}" ${(x.category ?? 'gold') === k ? 'selected' : ''}>${t}</option>`).join('')}</select></label></div>`,
    goal: `<label class="field"><span>Ad</span><input name="title" value="${esc(x.title ?? '')}" required></label>
      <div class="grid2"><label class="field"><span>Tür</span><select name="kind"><option value="netWorth" ${x.kind !== 'quantity' ? 'selected' : ''}>Net varlık</option><option value="quantity" ${x.kind === 'quantity' ? 'selected' : ''}>Ürün miktarı</option></select></label>
      <label class="field"><span>Hedef</span><input name="target" inputmode="decimal" value="${x.target ? fmt.editable(Number(x.target)) : ''}" required></label></div>
      <div class="grid2"><label class="field"><span>Ürün (miktar hedefi için)</span><select name="assetID"><option value="">—</option>${options(ledger.assets, x.assetID)}</select></label>
      <label class="field"><span>Kişi</span><select name="personID"><option value="">Herkes</option>${options(ledger.people, x.personID)}</select></label></div>`,
  };
  openModal(`<form>${formHead(existing ? titles[type] : `Yeni ${titles[type].toLocaleLowerCase('tr')}`)}${fields[type]}
    <div class="error" id="problem">${inUse ? 'Bu kayıt işlemlerde kullanıldığı için silinemez.' : ''}</div>
    <div class="actions"><button class="btn primary" value="save">Kaydet</button>${existing && !inUse && existing.id !== LIRA_ID ? '<button class="btn danger" value="delete" formnovalidate>Sil</button>' : ''}</div>
  </form>`, {
    async onSubmit(form, action) {
      if (action === 'delete') {
        if (!confirm('Silinsin mi? İşlem geçmişinden geri getirebilirsiniz.')) return;
        return commit(act.deleteDefinition(ledger, type, existing), closeModal);
      }
      const now = new Date().toISOString();
      let data;
      if (type === 'person') data = { id: x.id ?? act.newID(), name: form.name.value.trim(), createdAt: x.createdAt ?? now };
      if (type === 'location') data = { id: x.id ?? act.newID(), name: form.name.value.trim(), kind: form.kind.value, createdAt: x.createdAt ?? now };
      if (type === 'asset') {
        data = { id: x.id ?? act.newID(), name: form.name.value.trim(), unit: inUse ? x.unit : form.unit.value, category: form.category.value,
          sortOrder: x.sortOrder ?? Math.max(0, ...ledger.assets.map((a) => a.sortOrder)) + 1, createdAt: x.createdAt ?? now };
      }
      if (type === 'goal') {
        const target = parseDecimal(form.target.value);
        if (!(target > 0)) return (form.querySelector('#problem').textContent = 'Hedef sıfırdan büyük bir sayı olmalı.');
        if (form.kind.value === 'quantity' && !form.assetID.value) return (form.querySelector('#problem').textContent = 'Miktar hedefi için ürün seçin.');
        data = { id: x.id ?? act.newID(), title: form.title.value.trim(), kind: form.kind.value, target: storageText(target), createdAt: x.createdAt ?? now,
          ...(form.kind.value === 'quantity' ? { assetID: form.assetID.value } : {}), ...(form.personID.value ? { personID: form.personID.value } : {}) };
      }
      if (!(data.name ?? data.title)) return;
      await commit(act.saveRecord(type, data), closeModal);
    },
  });
}

// MARK: Olaylar

document.addEventListener('click', async (event) => {
  const target = event.target.closest('[data-act]');
  if (!target) return;
  const { act: action, id, type } = target.dataset;
  if (action === 'signin') {
    try { await store.signIn(); } catch (error) { if (error.code !== 'auth/popup-closed-by-user') { failure = `Giriş başarısız: ${error.message}`; renderLogin(); } }
  } else if (action === 'signout') {
    if (confirm('Çıkış yapılsın mı?')) await store.signOut();
  } else if (action === 'tab') {
    ui.tab = id; remember(); render(); window.scrollTo(0, 0);
  } else if (action === 'filter') {
    ui.filter = id; remember(); render();
  } else if (action === 'grouping') {
    ui.grouping = id; remember(); render();
  } else if (action === 'history') {
    ui.history = id; render();
  } else if (action === 'new-trade') {
    openTrade();
  } else if (action === 'new-transfer') {
    openTransfer();
  } else if (action === 'open-record') {
    const t = ledger.transactionByID.get(id);
    if (t?.transferID) openTransfer(t.transferID); else if (t) openTrade(t);
  } else if (action === 'new-debt') {
    openDebtForm();
  } else if (action === 'open-debt') {
    openDebt(id);
  } else if (action === 'new-def') {
    openDefinition(type);
  } else if (action === 'edit-def') {
    const list = { person: ledger.people, location: ledger.locations, asset: ledger.assets, goal: ledger.goals }[type];
    openDefinition(type, list.find((x) => x.id === id));
  } else if (action === 'undo') {
    const entry = ledger.journal.find((e) => e.id === id);
    if (!entry) return;
    const result = act.undo(ledger, entry);
    if (result.error) return alert(result.error);
    toast.hidden = true;
    await commit(result.writes);
  }
});

document.addEventListener('input', (event) => {
  if (event.target.dataset.input === 'search') {
    ui.search = event.target.value;
    document.getElementById('list').innerHTML = recordList();
  }
});

document.addEventListener('submit', async (event) => {
  if (event.target.id !== 'prices') return;
  event.preventDefault();
  const changes = [];
  for (const input of event.target.querySelectorAll('input[name]')) {
    if (!input.value.trim() || input.value === input.dataset.original) continue;
    const price = parseDecimal(input.value);
    if (!(price > 0)) {
      document.getElementById('price-error').textContent = `${ledger.assetName(input.name)}: fiyat geçerli bir sayı değil.`;
      return;
    }
    if (price !== ledger.price(input.name)) changes.push({ assetID: input.name, price });
  }
  document.getElementById('price-error').textContent = changes.length ? '' : 'Değişen fiyat yok.';
  if (changes.length) await commit(act.savePrices(changes));
});
