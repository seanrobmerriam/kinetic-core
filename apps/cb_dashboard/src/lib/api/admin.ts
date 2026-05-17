import { api } from "../api";
import type {
  AdminPermissionGroup,
  AdminRole,
  AdminUser,
  AdminUserDetail,
  ListResponse,
} from "../types/admin";

export async function listUsers(): Promise<AdminUser[]> {
  const resp = await api<ListResponse<AdminUser>>("GET", "/users");
  return resp.items ?? [];
}

export async function createUser(payload: {
  email: string;
  password: string;
  role: "admin" | "operations" | "read_only";
}): Promise<AdminUser> {
  return api<AdminUser>("POST", "/users", payload);
}

export async function getUser(userId: string): Promise<AdminUserDetail> {
  return api<AdminUserDetail>("GET", `/users/${userId}`);
}

export async function updateUser(
  userId: string,
  payload: Partial<Pick<AdminUser, "email" | "role" | "status">>,
): Promise<AdminUser> {
  return api<AdminUser>("PATCH", `/users/${userId}`, payload);
}

export async function assignUserRole(userId: string, roleId: string): Promise<void> {
  await api("POST", `/users/${userId}/roles`, { role_id: roleId });
}

export async function unassignUserRole(userId: string, roleId: string): Promise<void> {
  await api("DELETE", `/users/${userId}/roles/${roleId}`);
}

export async function listRoles(): Promise<AdminRole[]> {
  const resp = await api<ListResponse<AdminRole>>("GET", "/roles");
  return resp.items ?? [];
}

export async function createRole(payload: {
  display_name: string;
  description: string;
}): Promise<AdminRole> {
  return api<AdminRole>("POST", "/roles", payload);
}

export async function updateRole(
  roleId: string,
  payload: Partial<Pick<AdminRole, "display_name" | "description" | "status">>,
): Promise<AdminRole> {
  return api<AdminRole>("PATCH", `/roles/${roleId}`, payload);
}

export async function getRolePermissions(roleId: string): Promise<string[]> {
  const resp = await api<{ role_id: string; permission_keys: string[] }>(
    "GET",
    `/roles/${roleId}/permissions`,
  );
  return resp.permission_keys ?? [];
}

export async function setRolePermissions(roleId: string, permissionKeys: string[]): Promise<void> {
  await api("PUT", `/roles/${roleId}/permissions`, { permission_keys: permissionKeys });
}

export async function listPermissionGroups(): Promise<AdminPermissionGroup[]> {
  const resp = await api<{ items: AdminPermissionGroup[]; total: number }>(
    "GET",
    "/permissions",
  );
  return resp.items ?? [];
}
