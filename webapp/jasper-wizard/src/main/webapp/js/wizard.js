'use strict';
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const api = (p) => 'api' + p;

async function postForm(path, data) {
  const body = new URLSearchParams(data).toString();
  const res = await fetch(api(path), {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body
  });
  return res.json();
}
async function getJson(path) {
  const res = await fetch(api(path));
  return res.json();
}

/* extract {uri,label} list from a JRS resources response (resourceLookup[]) */
function resourceList(json) {
  const arr = json && json.resourceLookup ? json.resourceLookup : [];
  return arr.map(r => ({ uri: r.uri, label: r.label || r.uri }));
}

/* ---------------------------------------------------------- tabs ---------- */
$$('.tab').forEach(t => t.addEventListener('click', () => {
  $$('.tab').forEach(x => x.classList.remove('active'));
  $$('.panel').forEach(x => x.classList.remove('active'));
  t.classList.add('active');
  $('#tab-' + t.dataset.tab).classList.add('active');
  if (t.dataset.tab === 'dashboard') loadReportPicker();
}));

/* ---------------------------------------------------- server health ------- */
(async function health() {
  const el = $('#serverInfo');
  try {
    const h = await getJson('/health');
    el.textContent = 'JasperServer: ' + h.server;
    el.classList.add('up');
  } catch (e) {
    el.textContent = 'JasperServer unreachable';
    el.classList.add('down');
  }
})();

/* ---------------------------------------------------- datasource list ----- */
async function loadDatasources() {
  const sel = $('#r_ds');
  sel.innerHTML = '<option>loading…</option>';
  try {
    const list = resourceList(await getJson('/datasources'));
    sel.innerHTML = '';
    if (!list.length) { sel.innerHTML = '<option value="">(none — create one first)</option>'; return; }
    list.forEach(d => {
      const o = document.createElement('option');
      o.value = d.uri; o.textContent = d.label + '  —  ' + d.uri;
      sel.appendChild(o);
    });
  } catch (e) { sel.innerHTML = '<option value="">error loading</option>'; }
}
loadDatasources();

/* =========================== REPORT WIZARD =============================== */
let step = 0;
const steps = $$('#tab-report .step');
const crumbs = $$('#reportSteps li');
function showStep(n) {
  step = Math.max(0, Math.min(steps.length - 1, n));
  steps.forEach((s, i) => s.classList.toggle('on', i === step));
  crumbs.forEach((c, i) => c.classList.toggle('on', i <= step));
  if (step === 3) buildReview();
}
$$('#tab-report .next').forEach(b => b.addEventListener('click', () => {
  if (step === 1 && !$('#r_name').value.trim()) { alert('Report name is required.'); return; }
  if (step === 1 && !$('#r_query').value.trim()) { alert('SQL query is required.'); return; }
  showStep(step + 1);
}));
$$('#tab-report .prev').forEach(b => b.addEventListener('click', () => showStep(step - 1)));

/* toggle chart option fields */
$('#r_chart').addEventListener('change', () => {
  $('#r_chartopts').classList.toggle('off', $('#r_chart').value === 'none');
});

function reportPayload() {
  return {
    name: $('#r_name').value.trim(),
    title: $('#r_title').value.trim(),
    subtitle: $('#r_subtitle').value.trim(),
    query: $('#r_query').value.trim(),
    db: $('#r_db').value,
    dataSourceUri: $('#r_ds').value,
    template: $('#r_template').value,
    chart: $('#r_chart').value,
    chartCategory: $('#r_chartCategory').value.trim(),
    chartValue: $('#r_chartValue').value.trim(),
    groupBy: $('#r_groupBy').value.trim(),
    pageSize: $('#r_pageSize').value,
    landscape: $('#r_landscape').checked,
    folder: $('#r_folder').value.trim() || '/reports/wizard',
    label: $('#r_title').value.trim() || $('#r_name').value.trim()
  };
}
function buildReview() {
  const p = reportPayload();
  $('#r_review').textContent =
    'Report     : ' + p.folder + '/' + p.name + '\n' +
    'Title      : ' + p.title + '\n' +
    'Data source: ' + p.dataSourceUri + '\n' +
    'Introspect : ' + p.db + '\n' +
    'Template   : ' + p.template + (p.chart !== 'none' ? '   Chart: ' + p.chart + ' (' + p.chartCategory + ' × ' + p.chartValue + ')' : '   (table only)') +
    (p.groupBy ? '\nGroup by   : ' + p.groupBy : '') +
    '\nPage       : ' + p.pageSize + (p.landscape ? ' landscape' : ' portrait') +
    '\n\nQuery:\n' + p.query;
}

$('#r_deploy').addEventListener('click', async () => {
  const btn = $('#r_deploy');
  const p = reportPayload();
  if (!p.dataSourceUri) { alert('Pick a data source (step 1) or create one first.'); return; }
  btn.disabled = true; btn.textContent = 'Deploying…';
  const box = $('#r_result'); box.hidden = false;
  $('#r_status').innerHTML = '<div class="banner">Running scaffold → compile → deploy…</div>';
  $('#r_preview').innerHTML = ''; $('#r_log').textContent = '';
  try {
    const res = await postForm('/reports', p);
    $('#r_log').textContent = res.output || res.error || JSON.stringify(res);
    if (res.ok) {
      $('#r_status').innerHTML = '<div class="banner ok">✓ Deployed to ' + res.reportUri + '</div>';
      $('#r_preview').innerHTML = '<iframe class="preview" src="' + res.previewUrl + '"></iframe>';
    } else {
      $('#r_status').innerHTML = '<div class="banner err">✗ Failed' +
        (res.failedStep ? ' at ' + res.failedStep : '') + ' — see log</div>';
    }
  } catch (e) {
    $('#r_status').innerHTML = '<div class="banner err">✗ ' + e.message + '</div>';
  } finally {
    btn.disabled = false; btn.textContent = 'Deploy report';
  }
});

/* ========================= DASHBOARD WIZARD ============================= */
async function loadReportPicker() {
  const box = $('#d_reports');
  box.innerHTML = '<em>loading…</em>';
  try {
    const folder = $('#d_folder').value.trim() || '/reports';
    const list = resourceList(await getJson('/reports?folder=' + encodeURIComponent(folder)));
    if (!list.length) { box.innerHTML = '<em>No reports found under ' + folder + '. Deploy a report first.</em>'; return; }
    box.innerHTML = '';
    list.forEach(r => {
      const row = document.createElement('label');
      row.className = 'row';
      row.innerHTML = '<input type="checkbox" value="' + r.uri + '"> <span>' + r.label +
        ' <small>' + r.uri + '</small></span>';
      box.appendChild(row);
    });
  } catch (e) { box.innerHTML = '<em>error loading reports</em>'; }
}
$('#d_refresh').addEventListener('click', loadReportPicker);

$('#d_deploy').addEventListener('click', async () => {
  const btn = $('#d_deploy');
  const name = $('#d_name').value.trim();
  const picked = $$('#d_reports input:checked').map(c => c.value);
  if (!name) { alert('Dashboard name is required.'); return; }
  if (!picked.length) { alert('Select at least one report tile.'); return; }
  btn.disabled = true; btn.textContent = 'Composing…';
  const box = $('#d_result'); box.hidden = false;
  $('#d_status').innerHTML = '<div class="banner">Composing dashboard…</div>';
  try {
    const res = await postForm('/dashboards', {
      name,
      label: $('#d_label').value.trim() || name,
      folder: $('#d_folder').value.trim() || '/reports/wizard',
      cols: $('#d_cols').value,
      reports: picked.join(',')
    });
    $('#d_log').textContent = res.output || res.error || JSON.stringify(res);
    if (res.ok) {
      $('#d_status').innerHTML = '<div class="banner ok">✓ Dashboard at ' + res.dashboardUri +
        ' — <a href="' + res.viewerUrl + '" target="_blank">open viewer ↗</a></div>';
    } else {
      $('#d_status').innerHTML = '<div class="banner err">✗ Failed — see log</div>';
    }
  } catch (e) {
    $('#d_status').innerHTML = '<div class="banner err">✗ ' + e.message + '</div>';
  } finally {
    btn.disabled = false; btn.textContent = 'Deploy dashboard';
  }
});

/* ========================= DATASOURCE FORM ============================= */
$('#s_create').addEventListener('click', async () => {
  const btn = $('#s_create');
  const uri = $('#s_uri').value.trim(), database = $('#s_database').value.trim();
  if (!uri || !database) { alert('Repository URI and database name are required.'); return; }
  btn.disabled = true; btn.textContent = 'Creating…';
  const box = $('#s_result'); box.hidden = false;
  $('#s_status').innerHTML = '<div class="banner">Creating data source…</div>';
  try {
    const res = await postForm('/datasources', {
      uri, database,
      label: $('#s_label').value.trim(),
      host: $('#s_host').value.trim(),
      port: $('#s_port').value.trim(),
      dbUser: $('#s_dbUser').value.trim(),
      dbPassword: $('#s_dbPassword').value
    });
    $('#s_log').textContent = res.output || res.error || JSON.stringify(res);
    if (res.ok) {
      $('#s_status').innerHTML = '<div class="banner ok">✓ Created ' + res.uri + '</div>';
      loadDatasources();   // refresh the report wizard's dropdown
    } else {
      $('#s_status').innerHTML = '<div class="banner err">✗ Failed — see log</div>';
    }
  } catch (e) {
    $('#s_status').innerHTML = '<div class="banner err">✗ ' + e.message + '</div>';
  } finally {
    btn.disabled = false; btn.textContent = 'Create data source';
  }
});
