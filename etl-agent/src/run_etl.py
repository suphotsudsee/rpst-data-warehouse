import datetime as dt
import json
import os
import random
import sqlite3
import sys
import time

import jwt
import requests
from dotenv import load_dotenv

load_dotenv()


def env(name, default=None):
    value = os.getenv(name, default)
    if value is None or value == "":
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def ensure_sample_sqlite(path):
    if os.path.exists(path):
        return

    connection = sqlite3.connect(path)
    try:
        connection.execute(
            """
            CREATE TABLE visits (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              patient_id TEXT NOT NULL,
              visit_date TEXT NOT NULL,
              service_type TEXT NOT NULL,
              is_refer_out INTEGER NOT NULL DEFAULT 0,
              is_emergency INTEGER NOT NULL DEFAULT 0
            )
            """
        )
        today = dt.date.today()
        rows = []
        service_types = ["opd", "chronic", "anc", "vaccine", "home"]
        for day_offset in range(0, 14):
            report_date = today - dt.timedelta(days=day_offset)
            for index in range(random.randint(25, 90)):
                rows.append(
                    (
                        f"P{random.randint(1, 350):05d}",
                        report_date.isoformat(),
                        random.choice(service_types),
                        1 if random.random() < 0.04 else 0,
                        1 if random.random() < 0.02 else 0,
                    )
                )
        connection.executemany(
            """
            INSERT INTO visits
              (patient_id, visit_date, service_type, is_refer_out, is_emergency)
            VALUES (?, ?, ?, ?, ?)
            """,
            rows,
        )
        connection.commit()
    finally:
        connection.close()


def aggregate_sqlite(path, report_date):
    ensure_sample_sqlite(path)
    connection = sqlite3.connect(path)
    connection.row_factory = sqlite3.Row
    try:
        row = connection.execute(
            """
            SELECT
              COUNT(*) AS total_visits,
              COUNT(DISTINCT patient_id) AS unique_patients,
              SUM(CASE WHEN service_type = 'chronic' THEN 1 ELSE 0 END) AS chronic_followups,
              SUM(CASE WHEN service_type = 'chronic' THEN 1 ELSE 0 END) AS ncd_dm_patients,
              SUM(CASE WHEN service_type = 'chronic' THEN 1 ELSE 0 END) AS ncd_ht_patients,
              SUM(CASE WHEN service_type = 'chronic' THEN 1 ELSE 0 END) AS ncd_dm_ht_patients,
              SUM(CASE WHEN service_type IN ('opd', 'chronic') THEN 1 ELSE 0 END) AS ncd_bp_screened,
              SUM(CASE WHEN service_type = 'chronic' THEN 1 ELSE 0 END) AS ncd_fbs_screened,
              0 AS missing_diagnosis,
              SUM(CASE WHEN service_type = 'anc' THEN 1 ELSE 0 END) AS anc_visits,
              SUM(CASE WHEN service_type = 'vaccine' THEN 1 ELSE 0 END) AS vaccine_visits,
              SUM(CASE WHEN service_type = 'home' THEN 1 ELSE 0 END) AS home_visits,
              SUM(is_refer_out) AS refer_out,
              SUM(is_emergency) AS emergency_cases
            FROM visits
            WHERE visit_date = ?
            """,
            (report_date,),
        ).fetchone()
    finally:
        connection.close()

    return {key: int(row[key] or 0) for key in row.keys()}


def create_token(facility_id):
    now = int(time.time())
    return jwt.encode(
        {
            "iss": env("JWT_ISSUER", "rpst-etl"),
            "aud": env("JWT_AUDIENCE", "rpst-central-api"),
            "iat": now,
            "exp": now + 300,
            "facility_id": facility_id,
            "scope": "etl:write",
        },
        env("JWT_SECRET"),
        algorithm="HS256",
    )


def main():
    facility_id = env("FACILITY_ID")
    report_date = os.getenv(
        "REPORT_DATE",
        (dt.date.today() - dt.timedelta(days=1)).isoformat(),
    )
    local_db_kind = env("LOCAL_DB_KIND", "sqlite")
    if local_db_kind != "sqlite":
        raise RuntimeError("This starter ETL supports sqlite. Replace aggregate_sqlite for HOSxP/MySQL.")

    metrics = aggregate_sqlite(env("LOCAL_DB_DSN", "/app/sample_hosp.sqlite"), report_date)
    payload = {
        "facility_id": facility_id,
        "facility_name": env("FACILITY_NAME"),
        "district": os.getenv("DISTRICT"),
        "province": os.getenv("PROVINCE"),
        "report_date": report_date,
        "source_generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        **metrics,
        "payload": {
            "source": local_db_kind,
            "schema_version": "1.0",
            "generated_by": "rpst-etl-agent",
        },
    }

    response = requests.post(
        env("CENTRAL_API_URL"),
        headers={
            "Authorization": f"Bearer {create_token(facility_id)}",
            "Content-Type": "application/json",
        },
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        timeout=20,
    )
    if response.status_code >= 300:
        print(response.text, file=sys.stderr)
        response.raise_for_status()
    print(json.dumps(response.json(), ensure_ascii=False))


if __name__ == "__main__":
    main()
