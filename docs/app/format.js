// Telefondaki Format'ın karşılığı: bütün sayı ve tarihler tr_TR biçiminde (₺1.234,50, %12,5, 13 Kas 2026).

const L = 'tr-TR';
const liraFormat = new Intl.NumberFormat(L, { style: 'currency', currency: 'TRY' });
const currencyFormats = {
  $: new Intl.NumberFormat(L, { style: 'currency', currency: 'USD' }),
  '€': new Intl.NumberFormat(L, { style: 'currency', currency: 'EUR' }),
  '₺': liraFormat,
};
const percentFormat = new Intl.NumberFormat(L, { style: 'percent', maximumFractionDigits: 1 });
const dateFormat = new Intl.DateTimeFormat(L, { day: 'numeric', month: 'short', year: 'numeric' });
const dateTimeFormat = new Intl.DateTimeFormat(L, { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
const monthFormat = new Intl.DateTimeFormat(L, { month: 'long', year: 'numeric' });

export const fmt = {
  lira: (v) => liraFormat.format(v || 0),
  signedLira: (v) => (v > 0 ? '+' : v < 0 ? '−' : '') + liraFormat.format(Math.abs(v || 0)),
  number: (v, max = 4) => new Intl.NumberFormat(L, { maximumFractionDigits: max }).format(v || 0),
  quantity(v, unit) {
    if (currencyFormats[unit]) return currencyFormats[unit].format(v || 0);
    return `${fmt.number(v)} ${unit}`;
  },
  percent: (r) => percentFormat.format(r || 0),
  signedPercent: (r) => (r > 0 ? '+' : '') + percentFormat.format(r || 0),
  date: (d) => dateFormat.format(new Date(d)),
  dateTime: (d) => dateTimeFormat.format(new Date(d)),
  month: (d) => monthFormat.format(new Date(d)),
  /// Forma yazılacak hâl: binlik ayraçsız, virgüllü ondalık.
  editable: (v) => (v == null ? '' : String(Number(v.toFixed(10))).replace('.', ',')),
};

/// "1.234,50", "12,5", "0.25", "₺2.950" gibi girişleri okur; geçersizse null. Telefondaki parseDecimal ile aynı kural:
/// virgül yoksa, ardından tam üç rakam gelen nokta binlik ayraç sayılır.
export function parseDecimal(text) {
  let s = String(text ?? '').replace(/₺/g, '').replace(/\s/g, '');
  if (!s) return null;
  if (s.includes(',')) {
    s = s.replace(/\./g, '').replace(',', '.');
  } else {
    const dots = (s.match(/\./g) || []).length;
    const last = s.lastIndexOf('.');
    if (dots > 1 || (last >= 0 && s.length - last - 1 === 3)) s = s.replace(/\./g, '');
  }
  if (!/^-?\d*\.?\d+$/.test(s)) return null;
  const value = Number(s);
  return Number.isFinite(value) ? value : null;
}

/// Telefonun saklama biçimi: noktalı ondalık, bilimsel gösterim yok ("1234.5", "0.0001").
export function storageText(v) {
  return Number(v).toFixed(10).replace(/\.?0+$/, '') || '0';
}

export function esc(text) {
  return String(text ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

/// Yerel günün başlangıcı (telefon da işlem tarihini günün başına yuvarlar).
export function startOfDay(date) {
  const d = new Date(date);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

/// <input type="date"> değeri ↔ tarih.
export const dateInput = {
  value(d) {
    const x = new Date(d);
    return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`;
  },
  parse(v) {
    const [y, m, day] = String(v).split('-').map(Number);
    return y ? new Date(y, m - 1, day) : startOfDay(new Date());
  },
};
