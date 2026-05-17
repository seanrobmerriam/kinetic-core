export interface AdminUser {
  user_id: string;
  email: string;
  role: "admin" | "operations" | "read_only";
  status: string;
  created_at: number;
  updated_at: number;
}

export interface AdminRole {
  role_id: string;
  role_key: string;
  display_name: string;
  description: string;
  status: "active" | "disabled";
  is_system: boolean;
  created_at: number;
  updated_at: number;
}

export interface AdminPermission {
  permission_id: string;
  permission_key: string;
  resource: string;
  action: string;
  description: string;
  status: "active" | "disabled";
  created_at: number;
  updated_at: number;
}

export interface AdminPermissionGroup {
  resource: string;
  permissions: AdminPermission[];
}

export interface AdminUserDetail extends AdminUser {
  roles: AdminRole[];
  effective: {
    roles: string[];
    permissions: string[];
  };
}

export interface ListResponse<T> {
  items: T[];
  total: number;
}
