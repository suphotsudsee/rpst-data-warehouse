# UB-AMMS ER Diagram

```mermaid
erDiagram
    USERS ||--o{ MAPPINGS : creates_and_updates
    USERS ||--o{ AUDIT_LOGS : performs
    USERS ||--o{ APPROVALS : acts
    USERS ||--o{ BACKUPS : creates
    MAPPINGS ||--o{ APPROVALS : has

    USERS {
        uuid id PK
        varchar username UK
        varchar email UK
        varchar password_hash
        enum role
        boolean is_active
        datetime created_at
        datetime updated_at
    }
    MAPPINGS {
        uuid id PK
        int sequence
        varchar benefit_code
        varchar benefit_name
        varchar account_code
        varchar account_name
        text description
        date effective_date
        date expiry_date
        enum status
        int version
        boolean is_deleted
        uuid created_by FK
        uuid updated_by FK
        datetime created_at
        datetime updated_at
    }
    APPROVALS {
        uuid id PK
        uuid mapping_id FK
        enum action
        text comment
        uuid acted_by FK
        datetime created_at
    }
    AUDIT_LOGS {
        uuid id PK
        uuid user_id FK
        varchar action
        varchar entity_type
        uuid entity_id
        json old_value
        json new_value
        varchar ip_address
        varchar user_agent
        datetime created_at
    }
    BACKUPS {
        uuid id PK
        varchar label
        varchar reason
        json payload
        int record_count
        uuid created_by FK
        datetime created_at
    }
```

Business key ของ Mapping คือ `(benefit_code, account_code, effective_date)` และใช้ `version`
สำหรับ optimistic concurrency control เพื่อป้องกันผู้ใช้เขียนทับข้อมูลกันโดยไม่ตั้งใจ
