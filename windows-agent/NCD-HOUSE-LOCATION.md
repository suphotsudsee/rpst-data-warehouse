# NCD House Location Config

`scripts/RpstEtlAgent.ps1` already supports sending NCD house coordinates.

No script change is required if `config.json` contains:

```json
{
  "CentralLocationsApiUrl": "http://s14gjbvbsnmq1r2v3ujwh8nu.110.164.222.217.sslip.io/api/v1/etl/ncd-house-locations",
  "Sql": {
    "NcdHouseLocations": "SELECT DISTINCT CONCAT(v.pcucodeperson, ':', v.pid) AS patient_key, CASE WHEN d.diagcode REGEXP '^E1[0-4]' THEN 'DM' WHEN d.diagcode REGEXP '^I1[0-5]' THEN 'HT' ELSE 'NCD' END AS disease_group, CAST(TRIM(h.xgis) AS DECIMAL(10,7)) AS latitude, CAST(TRIM(h.ygis) AS DECIMAL(10,7)) AS longitude FROM visit v JOIN visitdiag d ON d.pcucode = v.pcucode AND d.visitno = v.visitno JOIN person p ON p.pcucodeperson = v.pcucodeperson AND p.pid = v.pid JOIN house h ON h.pcucode = p.pcucodeperson AND h.hcode = p.hcode WHERE v.visitdate = ? AND (d.diagcode REGEXP '^E1[0-4]' OR d.diagcode REGEXP '^I1[0-5]') AND TRIM(h.xgis) REGEXP '^-?[0-9]+(\\\\.[0-9]+)?$' AND TRIM(h.ygis) REGEXP '^-?[0-9]+(\\\\.[0-9]+)?$' AND CAST(TRIM(h.xgis) AS DECIMAL(10,7)) BETWEEN 5 AND 21 AND CAST(TRIM(h.ygis) AS DECIMAL(10,7)) BETWEEN 97 AND 106"
  }
}
```

For this JHCIS database:

- `house.xgis` is latitude.
- `house.ygis` is longitude.
- `patient_key` is hashed locally by the agent before sending.
- The agent does not send name, CID, HN, phone, or address.

