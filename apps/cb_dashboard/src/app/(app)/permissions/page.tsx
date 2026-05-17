"use client";

import { useEffect, useMemo, useState } from "react";
import { Badge, Button, Card, Group, Stack, Table, Text, Title } from "@mantine/core";
import {
  getRolePermissions,
  listPermissionGroups,
  listRoles,
} from "@/lib/api/admin";
import { useAuth } from "@/lib/auth";
import { useNotify } from "@/lib/notify";
import type { AdminPermissionGroup, AdminRole } from "@/lib/types/admin";

export default function PermissionsPage() {
  const { state } = useAuth();
  const { setError } = useNotify();

  const [permissionGroups, setPermissionGroups] = useState<AdminPermissionGroup[]>([]);
  const [roles, setRoles] = useState<AdminRole[]>([]);
  const [rolePermissions, setRolePermissions] = useState<Record<string, Set<string>>>({});
  const [loading, setLoading] = useState(true);

  const canAccess =
    state.status === "authenticated" &&
    (state.user.permissions?.includes("permission.read") || state.user.role === "admin");

  const refresh = async () => {
    setLoading(true);
    try {
      const [groups, roleList] = await Promise.all([listPermissionGroups(), listRoles()]);
      setPermissionGroups(groups);
      setRoles(roleList);

      const entries = await Promise.all(
        roleList.map(async (role) => {
          const permissionKeys = await getRolePermissions(role.role_id);
          return [role.role_id, new Set(permissionKeys)] as const;
        }),
      );
      const lookup: Record<string, Set<string>> = {};
      for (const [roleId, permissions] of entries) {
        lookup[roleId] = permissions;
      }
      setRolePermissions(lookup);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to load permission catalog");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void refresh();
  }, []);

  const rows = useMemo(
    () =>
      permissionGroups.flatMap((group) =>
        group.permissions.map((permission) => ({
          group: group.resource,
          permission,
          coveredBy: roles
            .filter((role) => rolePermissions[role.role_id]?.has(permission.permission_key))
            .map((role) => role.display_name),
        })),
      ),
    [permissionGroups, roles, rolePermissions],
  );

  if (!canAccess) {
    return (
      <Card withBorder>
        <Text c="red">You do not have permission to access Permissions.</Text>
      </Card>
    );
  }

  return (
    <Stack gap="lg">
      <Group justify="space-between">
        <Title order={3}>Permissions</Title>
        <Button variant="light" onClick={() => void refresh()} loading={loading}>
          Refresh
        </Button>
      </Group>

      <Card withBorder>
        <Table.ScrollContainer minWidth={1000}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Resource</Table.Th>
                <Table.Th>Permission Key</Table.Th>
                <Table.Th>Description</Table.Th>
                <Table.Th>Roles With Access</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {rows.map((row) => (
                <Table.Tr key={row.permission.permission_key}>
                  <Table.Td>{row.group}</Table.Td>
                  <Table.Td>
                    <Text fw={600}>{row.permission.permission_key}</Text>
                  </Table.Td>
                  <Table.Td>{row.permission.description}</Table.Td>
                  <Table.Td>
                    <Group gap="xs">
                      {row.coveredBy.map((name) => (
                        <Badge key={`${row.permission.permission_key}-${name}`} variant="light" color="blue">
                          {name}
                        </Badge>
                      ))}
                      {row.coveredBy.length === 0 && <Text c="dimmed">None</Text>}
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
              {rows.length === 0 && !loading && (
                <Table.Tr>
                  <Table.Td colSpan={4}>
                    <Text c="dimmed" ta="center">
                      No permissions found
                    </Text>
                  </Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Card>
    </Stack>
  );
}
