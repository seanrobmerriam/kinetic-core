"use client";

import { useEffect, useMemo, useState } from "react";
import {
  Badge,
  Button,
  Card,
  Group,
  Modal,
  Select,
  Stack,
  Table,
  Text,
  TextInput,
  Title,
} from "@mantine/core";
import {
  assignUserRole,
  createUser,
  getUser,
  listRoles,
  listUsers,
  unassignUserRole,
} from "@/lib/api/admin";
import { useAuth } from "@/lib/auth";
import { useNotify } from "@/lib/notify";
import type { AdminRole, AdminUser, AdminUserDetail } from "@/lib/types/admin";

const roleOptions = [
  { label: "Admin", value: "admin" },
  { label: "Operations", value: "operations" },
  { label: "Read Only", value: "read_only" },
] as const;

export default function UsersPage() {
  const { state } = useAuth();
  const { setError, setSuccess } = useNotify();

  const [users, setUsers] = useState<AdminUser[]>([]);
  const [roles, setRoles] = useState<AdminRole[]>([]);
  const [loading, setLoading] = useState(true);

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [createRoleValue, setCreateRoleValue] = useState<string | null>("read_only");

  const [manageOpen, setManageOpen] = useState(false);
  const [manageUser, setManageUser] = useState<AdminUserDetail | null>(null);
  const [assignRoleId, setAssignRoleId] = useState<string | null>(null);

  const canAccess =
    state.status === "authenticated" &&
    (state.user.permissions?.includes("user.read") || state.user.role === "admin");

  const refresh = async () => {
    setLoading(true);
    try {
      const [userList, roleList] = await Promise.all([listUsers(), listRoles()]);
      setUsers(userList);
      setRoles(roleList);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to load users");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void refresh();
  }, []);

  const openManage = async (userId: string) => {
    try {
      const detail = await getUser(userId);
      setManageUser(detail);
      setAssignRoleId(null);
      setManageOpen(true);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to load user details");
    }
  };

  const assign = async () => {
    if (!manageUser || !assignRoleId) return;
    try {
      await assignUserRole(manageUser.user_id, assignRoleId);
      const detail = await getUser(manageUser.user_id);
      setManageUser(detail);
      setAssignRoleId(null);
      setSuccess("Role assigned");
      await refresh();
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to assign role");
    }
  };

  const unassign = async (roleId: string) => {
    if (!manageUser) return;
    try {
      await unassignUserRole(manageUser.user_id, roleId);
      const detail = await getUser(manageUser.user_id);
      setManageUser(detail);
      setSuccess("Role unassigned");
      await refresh();
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to unassign role");
    }
  };

  const create = async () => {
    if (!email || !password || !createRoleValue) {
      setError("Email, password, and role are required");
      return;
    }
    if (
      createRoleValue !== "admin" &&
      createRoleValue !== "operations" &&
      createRoleValue !== "read_only"
    ) {
      setError("Invalid role");
      return;
    }
    try {
      await createUser({ email, password, role: createRoleValue });
      setEmail("");
      setPassword("");
      setCreateRoleValue("read_only");
      setSuccess("User created");
      await refresh();
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to create user");
    }
  };

  const availableRoleOptions = useMemo(() => {
    const assigned = new Set((manageUser?.roles ?? []).map((r) => r.role_id));
    return roles
      .filter((r) => !assigned.has(r.role_id))
      .map((r) => ({ label: r.display_name, value: r.role_id }));
  }, [roles, manageUser]);

  if (!canAccess) {
    return (
      <Card withBorder>
        <Text c="red">You do not have permission to access Users.</Text>
      </Card>
    );
  }

  return (
    <Stack gap="lg">
      <Group justify="space-between">
        <Title order={3}>Users</Title>
        <Button variant="light" onClick={() => void refresh()} loading={loading}>
          Refresh
        </Button>
      </Group>

      <Card withBorder>
        <Stack gap="sm">
          <Text fw={600}>Create User</Text>
          <Group grow align="flex-end">
            <TextInput
              label="Email"
              value={email}
              onChange={(e) => setEmail(e.currentTarget.value)}
              placeholder="user@example.com"
            />
            <TextInput
              label="Password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.currentTarget.value)}
              placeholder="Temporary password"
            />
            <Select
              label="Role"
              data={roleOptions as unknown as { label: string; value: string }[]}
              value={createRoleValue}
              onChange={setCreateRoleValue}
              allowDeselect={false}
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
                <Table.Th>Email</Table.Th>
                <Table.Th>Primary Role</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {users.map((user) => (
                <Table.Tr key={user.user_id}>
                  <Table.Td>{user.email}</Table.Td>
                  <Table.Td>{user.role}</Table.Td>
                  <Table.Td>
                    <Badge color={user.status === "active" ? "green" : "gray"} variant="light">
                      {user.status}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    <Button size="xs" variant="light" onClick={() => void openManage(user.user_id)}>
                      Manage Roles
                    </Button>
                  </Table.Td>
                </Table.Tr>
              ))}
              {users.length === 0 && !loading && (
                <Table.Tr>
                  <Table.Td colSpan={4}>
                    <Text c="dimmed" ta="center">
                      No users found
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
        title={manageUser ? `Roles for ${manageUser.email}` : "Manage roles"}
        size="lg"
      >
        <Stack gap="md">
          <Group grow align="flex-end">
            <Select
              label="Assign role"
              data={availableRoleOptions}
              value={assignRoleId}
              onChange={setAssignRoleId}
              placeholder="Select role"
            />
            <Button onClick={() => void assign()} disabled={!assignRoleId}>
              Assign
            </Button>
          </Group>

          <Stack gap="xs">
            {(manageUser?.roles ?? []).map((role) => (
              <Group key={role.role_id} justify="space-between">
                <div>
                  <Text fw={600}>{role.display_name}</Text>
                  <Text size="sm" c="dimmed">
                    {role.role_key}
                  </Text>
                </div>
                <Button
                  size="xs"
                  variant="light"
                  color="red"
                  onClick={() => void unassign(role.role_id)}
                >
                  Unassign
                </Button>
              </Group>
            ))}
            {(manageUser?.roles ?? []).length === 0 && (
              <Text c="dimmed">No assigned roles.</Text>
            )}
          </Stack>
        </Stack>
      </Modal>
    </Stack>
  );
}
