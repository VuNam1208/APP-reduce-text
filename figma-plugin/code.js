// Plugins → Development → Import plugin from manifest… → chọn manifest.json → Run

function c(hex) {
  const n = parseInt(hex.slice(1), 16);
  return { r: ((n >> 16) & 255) / 255, g: ((n >> 8) & 255) / 255, b: (n & 255) / 255 };
}
function solid(hex) {
  return [{ type: 'SOLID', color: c(hex) }];
}

const FONT = {
  async load() {
    for (const style of ['Regular', 'Semi Bold', 'Bold', 'Extra Bold']) {
      await figma.loadFontAsync({ family: 'Inter', style });
    }
  },
  w(weight) {
    const m = { 400: 'Regular', 600: 'Semi Bold', 700: 'Bold', 800: 'Extra Bold' };
    return { family: 'Inter', style: m[weight] || 'Regular' };
  },
};

async function txt(str, size, weight, color, width) {
  const t = figma.createText();
  t.fontName = FONT.w(weight);
  t.characters = str;
  t.fontSize = size;
  t.fills = solid(color);
  if (width) {
    t.textAutoResize = 'HEIGHT';
    t.resize(width, t.height);
  }
  return t;
}

function frame(name, o) {
  o = o || {};
  const f = figma.createFrame();
  f.name = name;
  f.layoutMode = o.dir || 'VERTICAL';
  f.itemSpacing = o.gap || 0;
  const p = o.pad || 0;
  f.paddingTop = o.pt != null ? o.pt : p;
  f.paddingBottom = o.pb != null ? o.pb : p;
  f.paddingLeft = o.pl != null ? o.pl : p;
  f.paddingRight = o.pr != null ? o.pr : p;
  if (o.fill) f.fills = solid(o.fill);
  if (o.stroke) {
    f.strokes = solid(o.stroke);
    f.strokeWeight = 1;
  }
  if (o.r) f.cornerRadius = o.r;
  f.primaryAxisAlignItems = o.pAlign || 'MIN';
  f.counterAxisAlignItems = o.cAlign || 'MIN';
  f.primaryAxisSizingMode = o.pSize || 'AUTO';
  f.counterAxisSizingMode = o.cSize || 'FIXED';
  if (o.w) f.resize(o.w, f.height || 100);
  return f;
}

function findByName(root, name) {
  if (root.name === name) return root;
  if ('children' in root) {
    for (const ch of root.children) {
      const f = findByName(ch, name);
      if (f) return f;
    }
  }
  return null;
}

function findPageFrame(name) {
  for (const n of figma.currentPage.children) {
    if (n.name.indexOf(name) >= 0) return n;
  }
  return null;
}

async function btn(label, primary, w) {
  const b = frame('Btn', {
    dir: 'HORIZONTAL',
    pAlign: 'CENTER',
    cAlign: 'CENTER',
    fill: primary ? '#2563EB' : '#FFFFFF',
    stroke: primary ? null : '#D7DEEA',
    r: 8,
    pt: 12,
    pb: 12,
    pl: 16,
    pr: 16,
    pSize: 'FIXED',
    cSize: 'AUTO',
  });
  b.resize(w, 46);
  b.appendChild(await txt(label, 14, 600, primary ? '#FFFFFF' : '#111827'));
  return b;
}

async function buildPhoneShell(name, x) {
  const phone = frame(name, { w: 390, fill: '#F6F8FC', pad: 12, gap: 10, pSize: 'FIXED', cSize: 'FIXED' });
  phone.resize(390, 844);
  phone.x = x;
  phone.y = 0;

  const header = frame('Header', {
    dir: 'HORIZONTAL',
    fill: '#FFFFFF',
    stroke: '#E1E8F2',
    r: 8,
    pad: 22,
    cAlign: 'CENTER',
    pSize: 'FIXED',
    cSize: 'AUTO',
  });
  header.appendChild(await txt('Text Summarizer', 22, 800, '#111827'));
  const sb = frame('Settings', { fill: '#E8EEF9', r: 8, pAlign: 'CENTER', cAlign: 'CENTER', pSize: 'FIXED', cSize: 'FIXED' });
  sb.resize(40, 40);
  sb.appendChild(await txt('S', 14, 700, '#2563EB'));
  header.appendChild(sb);
  phone.appendChild(header);
  header.layoutSizingHorizontal = 'FILL';

  const card = frame('Workspace', { fill: '#FFFFFF', stroke: '#E4EAF3', r: 8, pad: 14, gap: 12, pSize: 'FIXED', cSize: 'AUTO' });
  phone.appendChild(card);
  card.layoutGrow = 1;
  return { phone, card };
}

async function seg(labels, active) {
  const row = frame('Segment', { dir: 'HORIZONTAL', gap: 0, stroke: '#E4EAF3', r: 8, pSize: 'FIXED', cSize: 'AUTO' });
  for (let i = 0; i < labels.length; i++) {
    const on = i === active;
    const cell = frame('Seg', {
      fill: on ? '#2563EB' : '#FFFFFF',
      stroke: on ? null : '#E4EAF3',
      r: 8,
      pad: 10,
      pSize: 'AUTO',
      cSize: 'AUTO',
    });
    cell.appendChild(await txt(labels[i], 12, 600, on ? '#FFFFFF' : '#111827'));
    row.appendChild(cell);
  }
  return row;
}

async function settingCard(label, value, control) {
  const card = frame('SettingItem', { fill: '#F8FAFC', stroke: '#E4EAF3', r: 8, pad: 12, gap: 6, pSize: 'FIXED', cSize: 'AUTO' });
  card.appendChild(await txt(label, 13, 700, '#111827'));
  if (value) card.appendChild(await txt(value, 12, 400, '#697586'));
  if (control) card.appendChild(control);
  card.layoutSizingHorizontal = 'FILL';
  return card;
}

async function buildSettingsScreen() {
  let phone = findPageFrame('05');
  if (!phone) {
    const src = findPageFrame('01') || findPageFrame('Home');
    if (src) {
      phone = src.clone();
      phone.name = '05 — Settings';
      phone.x = 1680;
      phone.y = 0;
      figma.currentPage.appendChild(phone);
    } else {
      const built = await buildPhoneShell('05 — Settings', 1680);
      phone = built.phone;
      const ph = frame('Placeholder', { fill: '#FBFCFE', stroke: '#E4EAF3', r: 8, pad: 16, gap: 8, pAlign: 'CENTER', cAlign: 'CENTER', pSize: 'FIXED', cSize: 'FILL' });
      ph.appendChild(await txt('No source yet', 14, 800, '#111827'));
      built.card.appendChild(ph);
      ph.layoutGrow = 1;
      figma.currentPage.appendChild(phone);
    }
  }

  const oldOverlay = findByName(phone, 'Overlay');
  if (oldOverlay) oldOverlay.remove();
  const oldSheet = findByName(phone, 'SettingsSheet');
  if (oldSheet) oldSheet.remove();

  const overlay = figma.createRectangle();
  overlay.name = 'Overlay';
  overlay.resize(390, 844);
  overlay.fills = [{ type: 'SOLID', color: { r: 0.067, g: 0.094, b: 0.153, a: 0.35 } }];
  phone.appendChild(overlay);
  overlay.layoutPositioning = 'ABSOLUTE';
  overlay.x = -12;
  overlay.y = -12;

  const sheet = frame('SettingsSheet', { fill: '#FFFFFF', r: 16, pad: 16, gap: 10, pSize: 'FIXED', cSize: 'AUTO' });
  sheet.resize(366, 520);
  phone.appendChild(sheet);
  sheet.layoutPositioning = 'ABSOLUTE';
  sheet.x = 12;
  sheet.y = 310;

  sheet.appendChild(await txt('Settings', 16, 800, '#111827'));

  const langCtrl = frame('Dropdown', { fill: '#FFFFFF', stroke: '#E4EAF3', r: 8, pad: 10, pSize: 'FIXED', cSize: 'AUTO' });
  langCtrl.appendChild(await txt('Auto EN/VI  ▼', 13, 400, '#111827'));
  sheet.appendChild(await settingCard('Language', 'Auto EN/VI', langCtrl));

  sheet.appendChild(await settingCard('AI quality', 'Nhanh/Tiết kiệm', await seg(['Nhanh/Tiết kiệm', 'Chất lượng cao'], 0)));

  const slider = frame('Slider', { dir: 'HORIZONTAL', gap: 8, cAlign: 'CENTER', pSize: 'FIXED', cSize: 'AUTO' });
  const track = figma.createRectangle();
  track.resize(200, 4);
  track.fills = solid('#E4EAF3');
  track.cornerRadius = 2;
  slider.appendChild(track);
  const dot = figma.createEllipse();
  dot.resize(16, 16);
  dot.fills = solid('#2563EB');
  slider.appendChild(dot);
  slider.appendChild(await txt('10%', 13, 600, '#111827'));
  sheet.appendChild(await settingCard('Length of original', '10%', slider));

  const toggle = frame('Toggle', { fill: '#2563EB', r: 12, pSize: 'FIXED', cSize: 'FIXED' });
  toggle.resize(44, 24);
  toggle.layoutMode = 'HORIZONTAL';
  toggle.primaryAxisAlignItems = 'MAX';
  toggle.counterAxisAlignItems = 'CENTER';
  toggle.paddingRight = 4;
  const knob = figma.createEllipse();
  knob.resize(18, 18);
  knob.fills = solid('#FFFFFF');
  toggle.appendChild(knob);
  sheet.appendChild(await settingCard('OCR', 'On', toggle));

  sheet.appendChild(await settingCard('Export', 'TXT/PDF', await seg(['Both', 'TXT', 'PDF'], 0)));

  const reset = await btn('Reset length', false, 320);
  sheet.appendChild(reset);
  reset.layoutSizingHorizontal = 'FILL';

  return phone.id;
}

async function main() {
  await FONT.load();
  figma.currentPage.name = 'Screens';
  await buildSettingsScreen();
  figma.closePlugin();
}

main();
