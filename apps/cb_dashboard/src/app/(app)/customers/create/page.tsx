"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import {
  Button,
  Card,
  Group,
  Stack,
  TextInput,
  Title,
} from "@mantine/core";
import { api } from "@/lib/api";
import { useNotify } from "@/lib/notify";

export default function CreateCustomerPage() {
  const router = useRouter();
  const { setError, setSuccess } = useNotify();
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const create = async () => {
    if (!name || !email || submitting) return;
    setSubmitting(true);
    try {
      await api("POST", "/parties", { full_name: name, email });
      setSuccess("Customer created");
      router.push("/customers");
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Stack gap="lg">
      <Title order={3}>Create Customer</Title>

      <Card withBorder shadow="sm" radius="md" padding="lg" maw={600}>
        <Stack gap="md">
          <TextInput
            id="customer-name"
            label="Full Name"
            placeholder="Jane Smith"
            value={name}
            onChange={(e) => setName(e.currentTarget.value)}
            required
          />
          <TextInput
            id="customer-email"
            label="Email"
            placeholder="jane@example.com"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.currentTarget.value)}
            required
          />
          <Group mt="xs">
            <Button
              onClick={() => void create()}
              disabled={!name || !email || submitting}
              loading={submitting}
            >
              Create Customer
            </Button>
            <Button
              variant="subtle"
              onClick={() => router.push("/customers")}
            >
              Cancel
            </Button>
          </Group>
        </Stack>
      </Card>
    </Stack>
  );
}
