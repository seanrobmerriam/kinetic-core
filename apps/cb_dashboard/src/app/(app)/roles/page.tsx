"use client";

import { useEffect, useMemo, useState } from "react";
import {
  Badge,
  Button,
  Card,
  Checkbox,
  Group,
  Modal,
  Stack,
  Table,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import {
  createRole,
  getRolePermissions,
  listPermissionGroups,
  listRoles,
  setRolePermissions,
} from "@/lib/api/admin";
import { useAuth } from "@/lib/auth";
import { useNotify } from "@/lib/notify";
import type { AdminPermissionGroup, AdminRole } from "@/lib/types/admin";

export default function RolesPage() {
  const { state } = useAuth();
  const { setError, setSuccess } = useNotify();

  const [roles, setRoles] = useState<AdminRole[]>([]);
  const [permissionGroups, setPermissionGroups] = useState<AdminPermissionGroup[]>([]);
  const [loading, setLoading] = useState(true);

  const [displayName, setDisplayName] = useState("");
  const [description, setDescription] = useState("");

  const [manageOpen, setManageOpen] = useState(false);
  const [manageRole, setManageRole] = useState<AdminRole | null>(null);
  const [selectedPermissionKeys, setSelectedPermissionKeys] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);

  const canAccess =
    state.status === "authenticated" &&
    (state.user.permissions?.includes("role.read") || state.user.role === "admin");

  const refresh = async () => {
    setLoading(true);
    try {
      const [roleList, groups] = await Promise.all([listRoles(), listPermissionGroups()]);
      setRoles(roleList);
      setPermissionGroups(groups);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to load roles");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void refresh();
  }, []);

  const create = async () => {
    if (!displayName.trim()) {
      setError("Display name is required");
      return;
    }
    try {
      await createRole({ display_name: displayName.trim(), description: description.trim() });
      setDisplayName("");
      setDescription("");
      setSuccess("Role created");
      await refresh();
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to create role");
    }
  };

  const openManage = async (role: AdminRole) => {
    try {
      const currentPermissionKeys = await getRolePermissions(role.role_id);
      setManageRole(role);
      setSelectedPermissionKeys(currentPermissionKeys);
      setManageOpen(true);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to load role permissions");
    }
  };

  const togglePermission = (permissionKey: string, checked: boolean) => {
    setSelectedPermissionKeys((current) => {
      if (checked) return [...new Set([...current, permissionKey])];
      return current.filter((key) => key !== permissionKey);
    });
  };

  const savePermissions = async () => {
    if (!manageRole) return;
    setSaving(true);
    try {
      await setRolePermissions(manageRole.role_id, selectedPermissionKeys);
      setSuccess("Role permissions updated");
      setManageOpen(false);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to save role permissions");
    } finally {
      setSaving(false);
    }
  };

  const allPermissionKeys = useMemo(
    () => permissionGroups.flatMap((group) => group.permissions.map((p) => p.permission_key)),
    [permissionGroups],
  );

  if (!canAccess) {
    return (
      <Card withBorder>
        <Text c="red">You do not have permission to access Roles.</Text>
      </Card>
    );
  }

  return (
    <Stack gap="lg">
      <Group justify="space-between">
        <Title order={3}>Roles</Title>
        <Button variant="light" onClick={() => void refresh()} loading={loading}>
          Refresh
        </Button>
      </Group>

      <Card withBorder>
        <Stack gap="sm">
          <Text fw={600}>Create Role</Text>
          <Group grow align="flex-end">
            <TextInput
              label="Display name"
              value={displayName}
              onChange={(e) => setDisplayName(e.currentTarget.value)}
              placeholder="Support Analyst"
            />
            <TextInput
              label="Description"
              value={description}
              onChange={(e) => setDescription(e.currentTarget.value)}
              placeholder="Operational support role"
            />
            <Button onClick={() => void create()}>Create</Button>
          </Group>
        </Stack>
      </Card>

      <Card withBorder>
        <Table.ScrollContainer minWidth={900}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Display Name</Table.Th>
                <Table.Th>Key</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Type</Table.Th>
                <Table.Th>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {roles.map((role) => (
                <Table.Tr key={role.role_id}>
                  <Table.Td>{role.display_name}</Table.Td>
                  <Table.Td>{role.role_key}</Table.Td>
                  <Table.Td>
                    <Badge color={role.status === "active" ? "green" : "gray"} variant="light">
                      {role.status}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    <Badge color={role.is_system ? "blue" : "grape"} variant="light">
                      {role.is_system ? "System" : "Custom"}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    <Button size="xs" variant="light" onClick={() => void openManage(role)}>
                      Permissions
                    </Button>
                  </Table.Td>
                </Table.Tr>
              ))}
              {roles.length === 0 && !loading && (
                <Table.Tr>
                  <Table.Td colSpan={5}>
                    <Text c="dimmed" ta="center">
                      No roles found
                    </Text>
                  </Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Card>

      <Modal
        opened={manageOpen}
        onClose={() => setManageOpen(false)}
        title={manageRole ? `Permissions for ${manageRole.display_name}` : "Role permissions"}
        size="xl"
      >
        <Stack gap="md">
          {permissionGroups.map((group) => (
            <Card withBorder key={group.resource}>
              <Stack gap="xs">
                <Text fw={600}>{group.resource}</Text>
                {group.permissions.map((permission) => (
                  <Checkbox
                    key={permission.permission_key}
                    checked={selectedPermissionKeys.includes(permission.permission_key)}
                    onChange={(event) =>
                      togglePermission(permission.permission_key, event.currentTarget.checked)
                    }
                    label={`${permission.permission_key} - ${permission.description}`}
                  />
                ))}
              </Stack>
            </Card>
          ))}

          {allPermissionKeys.length === 0 && (
            <Text c="dimmed">No permissions available.</Text>
          )}

          <Group justify="flex-end">
            <Button variant="default" onClick={() => setManageOpen(false)}>
              Cancel
            </Button>
            <Button onClick={() => void savePermissions()} loading={saving}>
              Save
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
  );
}
