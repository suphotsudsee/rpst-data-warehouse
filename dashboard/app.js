const apiBaseUrl = window.API_BASE_URL || window.location.origin;

const palette = {
  blue: "#2563eb",
  amber: "#f59e0b",
  slate: "#475569",
  teal: "#0f766e",
  red: "#dc2626",
  green: "#16a34a",
  purple: "#7c3aed",
  line: "#dfe7f0",
  text: "#172033",
  muted: "#6b768a"
};

const diseaseColors = {
  DM: palette.red,
  HT: palette.amber,
  DM_HT: palette.blue,
  NCD: palette.blue,
  OTHER_NCD: palette.slate
};

let ncdMap = null;
let ncdLocationLayer = null;

const currentBeYear = new Date().getFullYear() + 543;
const yearState = {
  mode: "calendar",
  year: currentBeYear,
  pendingMode: "calendar",
  pendingYear: currentBeYear,
  availableYears: []
};

const formatNumber = (value) => new Intl.NumberFormat("th-TH").format(Number(value || 0));
const formatDateTime = (value) => (value ? new Date(value).toLocaleString("th-TH") : "-");
const compactDate = (value) => new Date(value).toLocaleDateString("th-TH", { month: "short", day: "numeric" });

const diseaseGroupLabels = [
  "ไขมันในเลือดสูง",
  "ปอดอักเสบจากการสูบบุหรี่ไฟฟ้า",
  "หลอดเลือดหัวใจ",
  "หลอดเลือดสมอง",
  "สุขภาพจิต",
  "มะเร็งทุกชนิด",
  "เบาหวาน",
  "ไอควาย",
  "ความดันโลหิตสูง",
  "ถุงลมโป่งพองเรื้อรัง"
];

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "\"": "&quot;",
    "'": "&#39;"
  })[char]);
}

function isoDate(date) {
  return date.toISOString().slice(0, 10);
}

function selectedRange() {
  const ceYear = yearState.year - 543;
  if (yearState.mode === "fiscal") {
    return {
      start: `${ceYear - 1}-10-01`,
      end: `${ceYear}-09-30`,
      label: `ปีงบประมาณ ${yearState.year}`
    };
  }
  return {
    start: `${ceYear}-01-01`,
    end: `${ceYear}-12-31`,
    label: `ปี พ.ศ. ${yearState.year}`
  };
}

function setupCanvas(canvas) {
  const rect = canvas.getBoundingClientRect();
  const scale = window.devicePixelRatio || 1;
  canvas.width = Math.max(1, Math.floor(rect.width * scale));
  canvas.height = Math.max(1, Math.floor(Number(canvas.getAttribute("height")) * scale));
  const ctx = canvas.getContext("2d");
  ctx.setTransform(scale, 0, 0, scale, 0, 0);
  return { ctx, width: rect.width, height: Number(canvas.getAttribute("height")) };
}

function drawNoData(ctx, width, height) {
  ctx.fillStyle = palette.muted;
  ctx.font = "13px Arial";
  ctx.textAlign = "center";
  ctx.fillText("ยังไม่มีข้อมูลสำหรับกราฟ", width / 2, height / 2);
}

function drawDonut(canvas, items) {
  const { ctx, width, height } = setupCanvas(canvas);
  ctx.clearRect(0, 0, width, height);
  const total = items.reduce((sum, item) => sum + item.value, 0);
  if (!total) {
    drawNoData(ctx, width, height);
    return;
  }

  const cx = width / 2;
  const cy = height / 2;
  const radius = Math.min(width, height) * 0.36;
  const inner = radius * 0.58;
  let start = -Math.PI / 2;

  items.forEach((item) => {
    const angle = (item.value / total) * Math.PI * 2;
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.arc(cx, cy, radius, start, start + angle);
    ctx.closePath();
    ctx.fillStyle = item.color;
    ctx.fill();
    start += angle;
  });

  ctx.beginPath();
  ctx.arc(cx, cy, inner, 0, Math.PI * 2);
  ctx.fillStyle = "#ffffff";
  ctx.fill();
  ctx.fillStyle = palette.text;
  ctx.font = "700 24px Arial";
  ctx.textAlign = "center";
  ctx.fillText(formatNumber(total), cx, cy - 2);
  ctx.fillStyle = palette.muted;
  ctx.font = "12px Arial";
  ctx.fillText("NCD signals", cx, cy + 18);
}

function drawVerticalBars(canvas, items) {
  const { ctx, width, height } = setupCanvas(canvas);
  ctx.clearRect(0, 0, width, height);
  const max = Math.max(...items.map((item) => item.value), 0);
  if (!max) {
    drawNoData(ctx, width, height);
    return;
  }

  const padding = { top: 18, right: 18, bottom: 42, left: 44 };
  const chartW = width - padding.left - padding.right;
  const chartH = height - padding.top - padding.bottom;
  const barW = chartW / items.length * 0.52;

  ctx.strokeStyle = palette.line;
  for (let i = 0; i <= 4; i++) {
    const y = padding.top + (chartH / 4) * i;
    ctx.beginPath();
    ctx.moveTo(padding.left, y);
    ctx.lineTo(width - padding.right, y);
    ctx.stroke();
  }

  items.forEach((item, index) => {
    const x = padding.left + (chartW / items.length) * index + (chartW / items.length - barW) / 2;
    const barH = chartH * (item.value / max);
    const y = padding.top + chartH - barH;
    ctx.fillStyle = item.color;
    ctx.fillRect(x, y, barW, barH);
    ctx.fillStyle = palette.text;
    ctx.font = "12px Arial";
    ctx.textAlign = "center";
    ctx.fillText(formatNumber(item.value), x + barW / 2, y - 6);
    ctx.fillStyle = palette.muted;
    ctx.fillText(item.label, x + barW / 2, height - 16);
  });
}

function drawHorizontalBars(canvas, items) {
  const { ctx, width, height } = setupCanvas(canvas);
  ctx.clearRect(0, 0, width, height);
  const visible = items.filter((item) => item.value > 0).slice(0, 7);
  const max = Math.max(...visible.map((item) => item.value), 0);
  if (!max) {
    drawNoData(ctx, width, height);
    return;
  }

  const left = 160;
  const right = 44;
  const top = 20;
  const rowH = Math.min(30, (height - 34) / visible.length);

  visible.forEach((item, index) => {
    const y = top + index * rowH;
    const barW = (width - left - right) * (item.value / max);
    ctx.fillStyle = palette.muted;
    ctx.font = "12px Arial";
    ctx.textAlign = "right";
    ctx.fillText(item.label.slice(0, 22), left - 10, y + 16);
    ctx.fillStyle = "#e8eef6";
    ctx.fillRect(left, y, width - left - right, 14);
    ctx.fillStyle = item.color;
    ctx.fillRect(left, y, barW, 14);
    ctx.fillStyle = palette.text;
    ctx.textAlign = "left";
    ctx.fillText(formatNumber(item.value), left + barW + 8, y + 12);
  });
}

function drawDiseaseBars(canvas, items) {
  const { ctx, width, height } = setupCanvas(canvas);
  ctx.clearRect(0, 0, width, height);
  const rows = items.map((item) => ({ ...item, value: Number(item.value || 0) }));
  const max = Math.max(...rows.map((item) => item.value), 0);
  if (!rows.length) {
    drawNoData(ctx, width, height);
    return;
  }

  const padding = { top: 18, right: 18, bottom: 34, left: Math.min(210, Math.max(142, width * 0.34)) };
  const chartW = Math.max(1, width - padding.left - padding.right);
  const chartH = height - padding.top - padding.bottom;
  const rowH = chartH / rows.length;
  const barH = Math.min(25, rowH * 0.72);
  const axisMax = Math.ceil(max / 100000) * 100000 || 1;

  ctx.strokeStyle = palette.line;
  ctx.fillStyle = palette.muted;
  ctx.font = "11px Arial";
  ctx.textAlign = "center";
  for (let i = 0; i <= 3; i++) {
    const value = axisMax * (i / 3);
    const x = padding.left + chartW * (i / 3);
    ctx.beginPath();
    ctx.moveTo(x, padding.top);
    ctx.lineTo(x, height - padding.bottom);
    ctx.stroke();
    ctx.fillText(formatNumber(Math.round(value)), x, height - 10);
  }

  ctx.strokeStyle = "#b8c4d4";
  ctx.beginPath();
  ctx.moveTo(padding.left, padding.top - 4);
  ctx.lineTo(padding.left, height - padding.bottom + 4);
  ctx.stroke();

  rows.forEach((item, index) => {
    const y = padding.top + index * rowH + (rowH - barH) / 2;
    const barW = chartW * (item.value / axisMax);
    const visibleBarW = item.value > 0 ? Math.max(barW, 2) : 0;
    const radius = Math.min(8, barH / 2, visibleBarW / 2);

    ctx.fillStyle = palette.text;
    ctx.font = "12px Arial";
    ctx.textAlign = "right";
    ctx.fillText(item.label, padding.left - 10, y + barH * 0.68);

    if (visibleBarW > 0) {
      ctx.fillStyle = palette.blue;
      ctx.beginPath();
      ctx.moveTo(padding.left + radius, y);
      ctx.lineTo(padding.left + visibleBarW - radius, y);
      ctx.quadraticCurveTo(padding.left + visibleBarW, y, padding.left + visibleBarW, y + radius);
      ctx.lineTo(padding.left + visibleBarW, y + barH - radius);
      ctx.quadraticCurveTo(padding.left + visibleBarW, y + barH, padding.left + visibleBarW - radius, y + barH);
      ctx.lineTo(padding.left + radius, y + barH);
      ctx.quadraticCurveTo(padding.left, y + barH, padding.left, y + barH - radius);
      ctx.lineTo(padding.left, y + radius);
      ctx.quadraticCurveTo(padding.left, y, padding.left + radius, y);
      ctx.fill();
    }

    ctx.fillStyle = item.value > axisMax * 0.12 ? "#1f3b57" : palette.text;
    ctx.font = "10px Arial";
    ctx.textAlign = item.value > axisMax * 0.12 ? "right" : "left";
    const labelX = item.value > axisMax * 0.12
      ? padding.left + visibleBarW - 8
      : padding.left + visibleBarW + 6;
    ctx.fillText(formatNumber(item.value), labelX, y + barH * 0.65);
  });
}

function drawLineChart(canvas, rows) {
  const { ctx, width, height } = setupCanvas(canvas);
  ctx.clearRect(0, 0, width, height);
  if (!rows.length) {
    drawNoData(ctx, width, height);
    return;
  }

  const padding = { top: 18, right: 22, bottom: 38, left: 44 };
  const chartW = width - padding.left - padding.right;
  const chartH = height - padding.top - padding.bottom;
  const max = Math.max(...rows.map((row) => Math.max(row.total_visits, row.ncd_dm_ht_patients)), 1);

  ctx.strokeStyle = palette.line;
  for (let i = 0; i <= 4; i++) {
    const y = padding.top + (chartH / 4) * i;
    ctx.beginPath();
    ctx.moveTo(padding.left, y);
    ctx.lineTo(width - padding.right, y);
    ctx.stroke();
  }

  [
    { key: "total_visits", color: palette.blue },
    { key: "ncd_dm_ht_patients", color: palette.teal }
  ].forEach((line) => {
    ctx.beginPath();
    rows.forEach((row, index) => {
      const x = padding.left + (rows.length === 1 ? chartW : chartW * (index / (rows.length - 1)));
      const y = padding.top + chartH - chartH * (Number(row[line.key] || 0) / max);
      if (index === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.strokeStyle = line.color;
    ctx.lineWidth = 2;
    ctx.stroke();
  });

  rows.forEach((row, index) => {
    if (index % Math.ceil(rows.length / 6) !== 0 && index !== rows.length - 1) return;
    const x = padding.left + (rows.length === 1 ? chartW : chartW * (index / (rows.length - 1)));
    ctx.fillStyle = palette.muted;
    ctx.font = "11px Arial";
    ctx.textAlign = "center";
    ctx.fillText(compactDate(row.report_date), x, height - 14);
  });
}

function updateLegend(items) {
  const legend = document.getElementById("ncdLegend");
  legend.innerHTML = items.map((item) =>
    `<span style="--dot:${item.color}">${escapeHtml(item.label)} ${formatNumber(item.value)}</span>`
  ).join("");
}

function colorForDiseaseGroup(group) {
  return diseaseColors[group] || palette.teal;
}

function initNcdMap() {
  const mapElement = document.getElementById("ncdMap");
  if (!mapElement || ncdMap || typeof L === "undefined") return;

  ncdMap = L.map(mapElement, {
    scrollWheelZoom: false
  }).setView([13.7563, 100.5018], 8);

  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution: "&copy; OpenStreetMap contributors"
  }).addTo(ncdMap);

  ncdLocationLayer = L.layerGroup().addTo(ncdMap);
}

function renderMapLocations(locationResult, scopeText) {
  const status = document.getElementById("mapStatus");
  const legend = document.getElementById("mapLegend");
  const caption = document.getElementById("mapCaption");
  caption.textContent = `House coordinates for NCD patients · ${scopeText}`;

  if (typeof L === "undefined") {
    status.textContent = "Map library is unavailable";
    return;
  }

  initNcdMap();
  ncdLocationLayer.clearLayers();

  const rows = locationResult.data || [];
  const groupCounts = {};
  rows.forEach((row) => {
    groupCounts[row.disease_group] = (groupCounts[row.disease_group] || 0) + 1;
  });

  legend.innerHTML = Object.entries(groupCounts).map(([group, count]) =>
    `<span style="--dot:${colorForDiseaseGroup(group)}">${escapeHtml(group)} ${formatNumber(count)}</span>`
  ).join("");

  if (!rows.length) {
    status.textContent = "No house coordinates found for the selected range";
    ncdMap.setView([13.7563, 100.5018], 8);
    setTimeout(() => ncdMap.invalidateSize(), 0);
    return;
  }

  const bounds = [];
  rows.forEach((row) => {
    const lat = Number(row.latitude);
    const lng = Number(row.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
    bounds.push([lat, lng]);
    L.circleMarker([lat, lng], {
      radius: 6,
      color: colorForDiseaseGroup(row.disease_group),
      fillColor: colorForDiseaseGroup(row.disease_group),
      fillOpacity: 0.74,
      weight: 1
    })
      .bindPopup(`
        <strong>${escapeHtml(row.disease_group)}</strong><br>
        ${escapeHtml(row.facility_name || row.facility_id)}<br>
        ${escapeHtml(row.report_date)}
      `)
      .addTo(ncdLocationLayer);
  });

  if (bounds.length) {
    ncdMap.fitBounds(bounds, { padding: [24, 24], maxZoom: 15 });
  }
  setTimeout(() => ncdMap.invalidateSize(), 0);
  status.textContent = `${formatNumber(rows.length)} shown` +
    (locationResult.total_locations > rows.length ? ` of ${formatNumber(locationResult.total_locations)}` : "");
}

function sumRows(rows) {
  return rows.reduce((acc, row) => {
    [
      "total_visits", "unique_patients", "chronic_followups", "ncd_dm_patients",
      "ncd_ht_patients", "ncd_dm_ht_patients", "ncd_bp_screened", "ncd_fbs_screened",
      "missing_diagnosis", "anc_visits", "vaccine_visits", "home_visits",
      "refer_out", "emergency_cases"
    ].forEach((key) => {
      acc[key] += Number(row[key] || 0);
    });
    return acc;
  }, {
    total_visits: 0,
    unique_patients: 0,
    chronic_followups: 0,
    ncd_dm_patients: 0,
    ncd_ht_patients: 0,
    ncd_dm_ht_patients: 0,
    ncd_bp_screened: 0,
    ncd_fbs_screened: 0,
    missing_diagnosis: 0,
    anc_visits: 0,
    vaccine_visits: 0,
    home_visits: 0,
    refer_out: 0,
    emergency_cases: 0
  });
}

async function fetchJson(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`API returned ${response.status}`);
  return response.json();
}

function selectedFacilityId() {
  return document.getElementById("facilityFilter").value;
}

function dashboardParams(start, end) {
  const params = new URLSearchParams({ start_date: start, end_date: end });
  const facilityId = selectedFacilityId();
  if (facilityId) params.set("facility_id", facilityId);
  return params.toString();
}

function renderYearList() {
  const list = document.getElementById("yearList");
  const label = document.getElementById("yearListLabel");
  const years = yearState.availableYears.length
    ? yearState.availableYears
    : [currentBeYear, currentBeYear - 1, currentBeYear - 2, currentBeYear - 3, currentBeYear - 4];

  label.textContent = yearState.pendingMode === "fiscal" ? "ตัวเลือก ปีงบประมาณ" : "ตัวเลือก ปี พ.ศ";
  document.querySelectorAll(".tab").forEach((tab) => {
    tab.classList.toggle("active", tab.dataset.mode === yearState.pendingMode);
  });
  list.innerHTML = years.map((year) =>
    `<button class="year-option ${year === yearState.pendingYear ? "selected" : ""}" type="button" data-year="${year}">${year}</button>`
  ).join("");
}

function updateYearButton() {
  document.getElementById("yearModeText").textContent = yearState.mode === "fiscal" ? "ปีงบประมาณ" : "ปี พ.ศ.";
  document.getElementById("selectedYearText").textContent = String(yearState.year);
}

function openYearPicker() {
  yearState.pendingMode = yearState.mode;
  yearState.pendingYear = yearState.year;
  renderYearList();
  document.getElementById("yearOverlay").hidden = false;
}

function closeYearPicker() {
  document.getElementById("yearOverlay").hidden = true;
}

function activateNavLink(activeLink) {
  document.querySelectorAll("nav a").forEach((link) => {
    link.classList.toggle("active", link === activeLink);
  });
}

function highlightSection(target) {
  document.querySelectorAll(".section-focus").forEach((section) => {
    section.classList.remove("section-focus");
  });
  target.classList.add("section-focus");
  target.setAttribute("tabindex", "-1");
  target.focus({ preventScroll: true });
  window.clearTimeout(target.__focusTimer);
  target.__focusTimer = window.setTimeout(() => {
    target.classList.remove("section-focus");
  }, 1600);
}

function bindSectionNav() {
  document.querySelectorAll("nav a[data-nav-target]").forEach((link) => {
    link.addEventListener("click", (event) => {
      event.preventDefault();
      const target = document.getElementById(link.dataset.navTarget);
      if (!target) return;
      activateNavLink(link);
      target.scrollIntoView({ behavior: "smooth", block: "start" });
      highlightSection(target);
      history.replaceState(null, "", link.getAttribute("href"));
    });
  });
}

async function loadOverview() {
  const statusText = document.getElementById("statusText");
  const reportDate = document.getElementById("reportDate").value;
  const range = selectedRange();
  const start = reportDate || range.start;
  const end = reportDate || range.end;
  const queryParams = dashboardParams(start, end);
  const facilitySelect = document.getElementById("facilityFilter");
  const facilityText = facilitySelect.value ? facilitySelect.options[facilitySelect.selectedIndex].textContent : "";

  statusText.textContent = "Loading";
  const [trends, facilityRange, diseaseGroups, locations] = await Promise.all([
    fetchJson(`${apiBaseUrl}/api/v1/dashboard/trends?${queryParams}`),
    fetchJson(`${apiBaseUrl}/api/v1/dashboard/facilities/range?${queryParams}`),
    fetchJson(`${apiBaseUrl}/api/v1/dashboard/disease-groups/range?${queryParams}`)
      .catch(() => ({ data: diseaseGroupLabels.map((label) => ({ disease_label: label, patients: 0 })) })),
    fetchJson(`${apiBaseUrl}/api/v1/dashboard/ncd-house-locations?${queryParams}`)
      .catch(() => ({ data: [], total_locations: 0, returned_locations: 0, groups: {} }))
  ]);

  const trendRows = trends.data || [];
  const facilities = facilityRange.facilities || [];
  const totals = sumRows(trendRows);
  const reportedFacilities = facilities.filter((facility) => Number(facility.reported_days || 0) > 0).length;
  const expectedFacilities = facilities.length || 90;
  const scopeText = [facilityText, reportDate ? "เฉพาะวันที่เลือก" : range.label].filter(Boolean).join(" · ");

  document.getElementById("reportedFacilities").textContent =
    `${formatNumber(reportedFacilities)}/${formatNumber(expectedFacilities)}`;
  document.getElementById("totalVisits").textContent = formatNumber(totals.total_visits);
  document.getElementById("uniquePatients").textContent = formatNumber(totals.unique_patients);
  document.getElementById("ncdDmHtPatients").textContent = formatNumber(totals.ncd_dm_ht_patients);
  document.getElementById("missingDiagnosis").textContent = formatNumber(totals.missing_diagnosis);
  document.getElementById("ncdBpScreened").textContent = formatNumber(totals.ncd_bp_screened);
  document.getElementById("totalVisitsScope").textContent = scopeText;
  document.getElementById("uniquePatientsScope").textContent = scopeText;
  document.getElementById("ncdScope").textContent = scopeText;
  document.getElementById("missingDxScope").textContent = scopeText;
  document.getElementById("bpScope").textContent = scopeText;
  document.getElementById("trendCaption").textContent = reportDate
    ? `Visits และ NCD วันที่ ${compactDate(reportDate)}`
    : `Visits และ NCD รายวัน ${range.label}`;
  document.getElementById("diseaseCaption").textContent = reportDate
    ? `จำนวนผู้ป่วยตามกลุ่มโรค วันที่ ${compactDate(reportDate)}`
    : `จำนวนผู้ป่วยตามกลุ่มโรค ${range.label}`;

  const ncdItems = [
    { label: "DM", value: totals.ncd_dm_patients, color: palette.red },
    { label: "HT", value: totals.ncd_ht_patients, color: palette.amber },
    { label: "BP", value: totals.ncd_bp_screened, color: palette.blue },
    { label: "FBS", value: totals.ncd_fbs_screened, color: palette.green }
  ];
  drawDonut(document.getElementById("ncdDonut"), ncdItems);
  updateLegend(ncdItems);
  drawLineChart(document.getElementById("trendLine"), trendRows);
  drawVerticalBars(document.getElementById("serviceBar"), [
    { label: "ANC", value: totals.anc_visits, color: palette.purple },
    { label: "Vaccine", value: totals.vaccine_visits, color: palette.green },
    { label: "Home", value: totals.home_visits, color: palette.teal },
    { label: "Refer", value: totals.refer_out, color: palette.amber },
    { label: "ER", value: totals.emergency_cases, color: palette.red }
  ]);
  drawHorizontalBars(document.getElementById("facilityBar"),
    facilities.map((facility) => ({
      label: facility.facility_name || facility.facility_id,
      value: Number(facility.total_visits || 0),
      color: palette.blue
    }))
  );
  drawDiseaseBars(document.getElementById("diseaseGroupBar"),
    (diseaseGroups.data || []).map((item) => ({
      label: item.disease_label,
      value: Number(item.patients || 0)
    }))
  );
  renderMapLocations(locations, scopeText);

  const rows = document.getElementById("facilityRows");
  rows.innerHTML = "";
  facilities.forEach((facility) => {
    const tr = document.createElement("tr");
    const rangeText = facility.last_report_date
      ? `${compactDate(facility.first_report_date)}-${compactDate(facility.last_report_date)}`
      : "ยังไม่มีข้อมูล";
    tr.innerHTML = `
      <td>${escapeHtml(facility.facility_id)}</td>
      <td>${escapeHtml(facility.facility_name)}</td>
      <td class="${facility.last_report_date ? "" : "missing"}">${rangeText}</td>
      <td class="number">${formatNumber(facility.total_visits)}</td>
      <td class="number">${formatNumber(facility.ncd_dm_ht_patients)}</td>
      <td class="number">${formatNumber(facility.ncd_dm_patients)}</td>
      <td class="number">${formatNumber(facility.ncd_ht_patients)}</td>
      <td class="number">${formatNumber(facility.ncd_bp_screened)}</td>
      <td class="number">${formatNumber(facility.ncd_fbs_screened)}</td>
      <td class="number">${formatNumber(facility.missing_diagnosis)}</td>
      <td class="number">${formatNumber(facility.anc_visits)}</td>
      <td class="number">${formatNumber(facility.vaccine_visits)}</td>
      <td class="number">${formatNumber(facility.home_visits)}</td>
      <td class="number">${formatNumber(facility.refer_out)}</td>
      <td>${formatDateTime(facility.received_at)}</td>
    `;
    rows.appendChild(tr);
  });

  statusText.textContent = `${scopeText} · Updated ${new Date().toLocaleTimeString("th-TH")}`;
}

async function loadAvailableYears() {
  try {
    const result = await fetchJson(`${apiBaseUrl}/api/v1/dashboard/available-years`);
    yearState.availableYears = (result.years || [])
      .map(Number)
      .filter((year) => year >= 2564);
    if (yearState.availableYears.length && !yearState.availableYears.includes(yearState.year)) {
      yearState.year = yearState.availableYears[0];
      yearState.pendingYear = yearState.year;
      updateYearButton();
    }
  } catch {
    yearState.availableYears = [2569, 2568, 2567, 2566, 2565, 2564];
  }
  renderYearList();
}

async function loadFacilityOptions() {
  const select = document.getElementById("facilityFilter");
  try {
    const result = await fetchJson(`${apiBaseUrl}/api/v1/facilities`);
    const facilities = result.data || [];
    select.innerHTML = `<option value="">ทุกหน่วยบริการ</option>` + facilities.map((facility) => {
      const label = `${facility.facility_id} - ${facility.facility_name || ""}`.trim();
      return `<option value="${escapeHtml(facility.facility_id)}">${escapeHtml(label)}</option>`;
    }).join("");
  } catch {
    select.innerHTML = `<option value="">ทุกหน่วยบริการ</option>`;
  }
}

document.getElementById("yearPickerButton").addEventListener("click", openYearPicker);
document.getElementById("yearOverlay").addEventListener("click", (event) => {
  if (event.target.id === "yearOverlay") closeYearPicker();
});
document.querySelectorAll(".tab").forEach((tab) => {
  tab.addEventListener("click", () => {
    yearState.pendingMode = tab.dataset.mode;
    renderYearList();
  });
});
document.getElementById("yearList").addEventListener("click", (event) => {
  const button = event.target.closest(".year-option");
  if (!button) return;
  yearState.pendingYear = Number(button.dataset.year);
  renderYearList();
});
document.getElementById("confirmYearButton").addEventListener("click", () => {
  yearState.mode = yearState.pendingMode;
  yearState.year = yearState.pendingYear;
  document.getElementById("reportDate").value = "";
  updateYearButton();
  closeYearPicker();
  loadOverview().catch((error) => {
    document.getElementById("statusText").textContent = error.message;
  });
});
document.getElementById("refreshButton").addEventListener("click", () => {
  loadOverview().catch((error) => {
    document.getElementById("statusText").textContent = error.message;
  });
});
document.getElementById("facilityFilter").addEventListener("change", () => {
  loadOverview().catch((error) => {
    document.getElementById("statusText").textContent = error.message;
  });
});
window.addEventListener("resize", () => {
  clearTimeout(window.__resizeTimer);
  window.__resizeTimer = setTimeout(loadOverview, 180);
});

updateYearButton();
bindSectionNav();
Promise.all([loadAvailableYears(), loadFacilityOptions()]).then(loadOverview).catch((error) => {
  document.getElementById("statusText").textContent = error.message;
});
