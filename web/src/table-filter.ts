/**
 * Filters for every data table of the portal (owner request 22/10/2026):
 * a search box over all columns plus a drop-down per column holding few
 * distinct values (statuses, types, categories...). Installed once on the
 * document, it enhances each <table> as it appears and follows the rows
 * Angular adds or removes. Opt out with <table data-nofilter>.
 * Filtering applies to the rows loaded on screen.
 */
const MAX_CHOICES = 12;
const MIN_ROWS = 2;
// Columns that get a drop-down whenever they hold at least two values.
const CATEGORY_HEADERS = /statut|paiement|type|cat[ée]gorie|r[ôo]le|dossier|profil|niveau|motif|action/i;

interface Enhanced { bar: HTMLElement; search: HTMLInputElement; selects: Map<number, HTMLSelectElement>; count: HTMLElement; reset: HTMLButtonElement; observer: MutationObserver; }
const enhanced = new Map<HTMLTableElement, Enhanced>();

export function normalize(s: string): string {
  return s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();
}

/** Value of a cell for a column filter: its status pills, otherwise its text. */
export function cellValue(cell: Element | undefined): string {
  if (!cell) return '';
  const pills = Array.from(cell.querySelectorAll('.pill')).map(p => (p.textContent || '').trim()).filter(Boolean);
  if (pills.length) return pills.join(' · ');
  // Detail lines (.sub: seats, e-mail...) do not make a category.
  const main = cell.cloneNode(true) as Element;
  main.querySelectorAll('.sub').forEach(s => s.remove());
  return (main.textContent || '').replace(/\s+/g, ' ').trim();
}

function rows(table: HTMLTableElement): HTMLTableRowElement[] {
  return Array.from(table.tBodies).flatMap(b => Array.from(b.rows));
}

function headers(table: HTMLTableElement): string[] {
  const head = table.tHead?.rows[0];
  return head ? Array.from(head.cells).map(c => (c.textContent || '').replace(/\s+/g, ' ').trim()) : [];
}

function enhance(table: HTMLTableElement) {
  if (enhanced.has(table) || table.hasAttribute('data-nofilter')) return;
  const host = table.closest('.tablewrap') || table;
  const bar = document.createElement('div');
  bar.className = 'tfilter';
  bar.setAttribute('role', 'search');
  const search = document.createElement('input');
  search.type = 'search';
  search.placeholder = 'Rechercher dans le tableau…';
  search.setAttribute('aria-label', 'Rechercher dans le tableau');
  search.className = 'tfilter-search';
  const count = document.createElement('span');
  count.className = 'tfilter-count';
  const reset = document.createElement('button');
  reset.type = 'button';
  reset.className = 'link tfilter-reset';
  reset.textContent = 'Réinitialiser';
  bar.append(search, count, reset);
  host.parentNode?.insertBefore(bar, host);

  const state: Enhanced = { bar, search, selects: new Map(), count, reset, observer: new MutationObserver(() => schedule(table)) };
  enhanced.set(table, state);
  search.addEventListener('input', () => apply(table));
  reset.addEventListener('click', () => {
    search.value = '';
    state.selects.forEach(s => (s.value = ''));
    apply(table);
  });
  state.observer.observe(table, { childList: true, subtree: true, characterData: true });
  refresh(table);
}

const pending = new Set<HTMLTableElement>();
function schedule(table: HTMLTableElement) {
  if (pending.has(table)) return;
  pending.add(table);
  requestAnimationFrame(() => { pending.delete(table); refresh(table); });
}

/** Rebuilds the column drop-downs from the current rows, keeping choices. */
function refresh(table: HTMLTableElement) {
  const st = enhanced.get(table);
  if (!st) return;
  const all = rows(table);
  const names = headers(table);
  const wanted = new Map<number, string[]>();
  names.forEach((name, i) => {
    if (!name) return;
    const values = Array.from(new Set(all.map(r => cellValue(r.cells[i])).filter(Boolean))).sort((a, b) => a.localeCompare(b, 'fr'));
    const category = CATEGORY_HEADERS.test(name) || all.some(r => r.cells[i]?.querySelector('.pill'));
    if (values.length >= 2 && values.length <= MAX_CHOICES && (category || values.length < all.length)) wanted.set(i, values);
  });
  st.selects.forEach((sel, i) => { if (!wanted.has(i)) { sel.remove(); st.selects.delete(i); } });
  wanted.forEach((values, i) => {
    let sel = st.selects.get(i);
    if (!sel) {
      sel = document.createElement('select');
      sel.className = 'tfilter-col';
      sel.setAttribute('aria-label', 'Filtrer : ' + names[i]);
      sel.addEventListener('change', () => apply(table));
      st.selects.set(i, sel);
      const after = Array.from(st.selects.keys()).sort((a, b) => a - b).find(k => k > i);
      st.bar.insertBefore(sel, after !== undefined && st.selects.get(after)?.parentNode ? st.selects.get(after)! : st.count);
    }
    const keep = sel.value;
    sel.replaceChildren(new Option(names[i] + ' : tous', ''), ...values.map(v => new Option(v, v)));
    sel.value = values.includes(keep) ? keep : '';
  });
  st.bar.hidden = all.length < MIN_ROWS && !st.search.value && Array.from(st.selects.values()).every(s => !s.value);
  apply(table);
}

function apply(table: HTMLTableElement) {
  const st = enhanced.get(table);
  if (!st) return;
  const q = normalize(st.search.value);
  const all = rows(table);
  let shown = 0;
  for (const r of all) {
    const textOk = !q || normalize(r.textContent || '').includes(q);
    let colsOk = true;
    st.selects.forEach((sel, i) => { if (sel.value && cellValue(r.cells[i]) !== sel.value) colsOk = false; });
    const visible = textOk && colsOk;
    r.style.display = visible ? '' : 'none';
    if (visible) shown++;
  }
  const active = !!q || Array.from(st.selects.values()).some(s => !!s.value);
  st.count.textContent = active ? `${shown} / ${all.length} ligne${all.length > 1 ? 's' : ''}` : `${all.length} ligne${all.length > 1 ? 's' : ''}`;
  st.reset.hidden = !active;
}

/** Drops the bars of tables Angular removed. */
function sweep() {
  enhanced.forEach((st, table) => {
    if (!table.isConnected) { st.observer.disconnect(); st.bar.remove(); enhanced.delete(table); }
  });
}

export function installTableFilters(root: HTMLElement = document.body) {
  const scan = () => { sweep(); root.querySelectorAll('table').forEach(t => enhance(t as HTMLTableElement)); };
  let queued = false;
  new MutationObserver(() => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => { queued = false; scan(); });
  }).observe(root, { childList: true, subtree: true });
  scan();
}
