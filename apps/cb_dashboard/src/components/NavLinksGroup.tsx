"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Box, Collapse, Group, Text, ThemeIcon, UnstyledButton } from "@mantine/core";
import { IconChevronRight, type Icon } from "@tabler/icons-react";
import classes from "./NavLinksGroup.module.css";

interface NavLinkItem {
  label: string;
  href: string;
}

interface NavLinksGroupProps {
  icon: Icon;
  label: string;
  href?: string;
  initiallyOpened?: boolean;
  links?: NavLinkItem[];
}

export function NavLinksGroup({
  icon: Icon,
  label,
  href,
  initiallyOpened,
  links,
}: NavLinksGroupProps) {
  const pathname = usePathname() ?? "";
  const hasLinks = Array.isArray(links) && links.length > 0;

  const isDirectlyActive = href
    ? pathname === href || pathname.startsWith(`${href}/`)
    : false;

  const isChildActive = hasLinks
    ? links!.some((l) => pathname === l.href || pathname.startsWith(`${l.href}/`))
    : false;

  const [opened, setOpened] = useState(initiallyOpened || isChildActive || false);

  const subItems = hasLinks
    ? links!.map((link) => (
        <Text<typeof Link>
          component={Link}
          className={classes.link}
          href={link.href}
          key={link.label}
          data-active={(pathname === link.href || pathname.startsWith(`${link.href}/`)) || undefined}
        >
          {link.label}
        </Text>
      ))
    : [];

  if (!hasLinks && href) {
    return (
      <UnstyledButton
        component={Link}
        href={href}
        className={classes.control}
        data-active={isDirectlyActive || undefined}
      >
        <Group justify="space-between" gap={0}>
          <Box style={{ display: "flex", alignItems: "center" }}>
            <ThemeIcon variant="light" size={30}>
              <Icon size={18} />
            </ThemeIcon>
            <Box ml="md">{label}</Box>
          </Box>
        </Group>
      </UnstyledButton>
    );
  }

  return (
    <>
      <UnstyledButton onClick={() => setOpened((o) => !o)} className={classes.control}>
        <Group justify="space-between" gap={0}>
          <Box style={{ display: "flex", alignItems: "center" }}>
            <ThemeIcon variant="light" size={30}>
              <Icon size={18} />
            </ThemeIcon>
            <Box ml="md">{label}</Box>
          </Box>
          {hasLinks && (
            <IconChevronRight
              className={classes.chevron}
              stroke={1.5}
              size={16}
              style={{ transform: opened ? "rotate(90deg)" : "none" }}
            />
          )}
        </Group>
      </UnstyledButton>
      {hasLinks ? <Collapse expanded={opened}>{subItems}</Collapse> : null}
    </>
  );
}
