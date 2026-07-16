export type Role = "viewer" | "editor" | "approver" | "super_admin";
export type MappingStatus = "draft" | "pending" | "approved" | "published" | "rejected";

export interface User {
  id: string;
  username: string;
  email: string;
  role: Role;
  is_active: boolean;
}

export interface Mapping {
  id: string;
  sequence: number;
  benefit_code: string;
  benefit_name: string;
  account_code: string;
  account_name: string;
  description: string | null;
  source_sheet: string | null;
  source_row: number | null;
  source_data: Record<string, string | number | null> | null;
  effective_date: string;
  expiry_date: string | null;
  status: MappingStatus;
  version: number;
  created_by: string;
  updated_by: string;
  created_at: string;
  updated_at: string;
}

export interface DashboardStats {
  mappings: number;
  benefits: number;
  account_codes: number;
  duplicates: number;
  validation_errors: number;
  pending_approval: number;
  latest_version: number;
  recent_activity: Array<{
    action: string;
    entity_type: string;
    entity_id: string | null;
    created_at: string;
  }>;
}
