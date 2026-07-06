const apiBaseUrl = window.API_BASE_URL || "http://localhost:8080";

const formatNumber = (value) => new Intl.NumberFormat("th-TH").format(Number(value || 0));
const formatDateTime = (value) => (value ? new Date(value).toLocaleString("th-TH") : "-");

async function loadOverview() {
  const statusText = document.getElementById("statusText");
  const reportDate = document.getElementById("reportDate").value;
  const url = new URL(`${apiBaseUrl}/api/v1/dashboard/overview`);
  if (reportDate) {
    url.searchParams.set("report_date", reportDate);
  }

  statusText.textContent = "Loading";
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`API returned ${response.status}`);
  }
  const overview = await response.json();
  const totals = overview.totals;

  document.getElementById("reportedFacilities").textContent =
    `${formatNumber(totals.facilities_reported)}/${formatNumber(totals.facilities_total || 90)}`;
  document.getElementById("totalVisits").textContent = formatNumber(totals.total_visits);
  document.getElementById("uniquePatients").textContent = formatNumber(totals.unique_patients);
  document.getElementById("ncdDmHtPatients").textContent = formatNumber(totals.ncd_dm_ht_patients);
  document.getElementById("ncdDmPatients").textContent = formatNumber(totals.ncd_dm_patients);
  document.getElementById("ncdHtPatients").textContent = formatNumber(totals.ncd_ht_patients);
  document.getElementById("ncdBpScreened").textContent = formatNumber(totals.ncd_bp_screened);
  document.getElementById("ncdFbsScreened").textContent = formatNumber(totals.ncd_fbs_screened);
  document.getElementById("missingDiagnosis").textContent = formatNumber(totals.missing_diagnosis);
  document.getElementById("referOut").textContent = formatNumber(totals.refer_out);
  document.getElementById("emergencyCases").textContent = formatNumber(totals.emergency_cases);

  const rows = document.getElementById("facilityRows");
  rows.innerHTML = "";
  overview.facilities.forEach((facility) => {
    const tr = document.createElement("tr");
    const reportDateText = facility.report_date || "ยังไม่มีข้อมูล";
    tr.innerHTML = `
      <td>${facility.facility_id}</td>
      <td>${facility.facility_name}</td>
      <td class="${facility.report_date ? "" : "missing"}">${reportDateText}</td>
      <td class="number">${formatNumber(facility.total_visits)}</td>
      <td class="number">${formatNumber(facility.chronic_followups)}</td>
      <td class="number">${formatNumber(facility.ncd_dm_ht_patients)}</td>
      <td class="number">${formatNumber(facility.ncd_dm_patients)}</td>
      <td class="number">${formatNumber(facility.ncd_ht_patients)}</td>
      <td class="number">${formatNumber(facility.ncd_bp_screened)}</td>
      <td class="number">${formatNumber(facility.ncd_fbs_screened)}</td>
      <td class="number">${formatNumber(facility.missing_diagnosis)}</td>
      <td class="number">${formatNumber(facility.anc_visits)}</td>
      <td class="number">${formatNumber(facility.vaccine_visits)}</td>
      <td class="number">${formatNumber(facility.home_visits)}</td>
      <td>${formatDateTime(facility.received_at)}</td>
    `;
    rows.appendChild(tr);
  });

  statusText.textContent = `Updated ${new Date().toLocaleTimeString("th-TH")}`;
}

document.getElementById("refreshButton").addEventListener("click", () => {
  loadOverview().catch((error) => {
    document.getElementById("statusText").textContent = error.message;
  });
});

loadOverview().catch((error) => {
  document.getElementById("statusText").textContent = error.message;
});
