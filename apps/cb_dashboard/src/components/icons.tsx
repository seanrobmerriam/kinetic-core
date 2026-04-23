import type { ComponentType, SVGProps } from "react";
import {
  ArrowDown,
  ArrowLeft,
  ArrowRight,
  ArrowUp,
  Bank,
  Book,
  Cash,
  ChatBubble,
  Check,
  Clock,
  Code,
  Coins,
  DataTransferBoth,
  Dollar,
  Download,
  Group,
  HalfMoon,
  JournalPage,
  Key,
  LogOut,
  Mail,
  MultiplePages,
  NavArrowDown,
  NavArrowRight,
  NavArrowUp,
  Network,
  Refresh,
  Reports,
  Search,
  Settings,
  Shield,
  ShieldCheck,
  Sort,
  SunLight,
  Upload,
  ViewGrid,
  Wallet,
  Plus,
  WarningCircle,
  WarningTriangle,
} from "iconoir-react";

type IconoirIcon = ComponentType<SVGProps<SVGSVGElement>>;

export type IconProps = Omit<SVGProps<SVGSVGElement>, "stroke"> & {
  size?: number | string;
  stroke?: number | string;
};

export type Icon = ComponentType<IconProps>;

function wrap(Inner: IconoirIcon, displayName: string): Icon {
  const Wrapped = ({
    size,
    stroke,
    width,
    height,
    strokeWidth,
    ...rest
  }: IconProps) => (
    <Inner
      width={size ?? width ?? 24}
      height={size ?? height ?? 24}
      strokeWidth={(stroke as number | string | undefined) ?? strokeWidth ?? 1.5}
      {...rest}
    />
  );
  Wrapped.displayName = displayName;
  return Wrapped;
}

export const IconAlertCircle = wrap(WarningCircle, "IconAlertCircle");
export const IconAlertTriangle = wrap(WarningTriangle, "IconAlertTriangle");
export const IconArrowDown = wrap(ArrowDown, "IconArrowDown");
export const IconArrowLeft = wrap(ArrowLeft, "IconArrowLeft");
export const IconArrowRight = wrap(ArrowRight, "IconArrowRight");
export const IconArrowUp = wrap(ArrowUp, "IconArrowUp");
export const IconAt = wrap(Mail, "IconAt");
export const IconBook = wrap(Book, "IconBook");
export const IconBuildingBank = wrap(Bank, "IconBuildingBank");
export const IconCash = wrap(Cash, "IconCash");
export const IconCashBanknote = wrap(Cash, "IconCashBanknote");
export const IconCheck = wrap(Check, "IconCheck");
export const IconChevronDown = wrap(NavArrowDown, "IconChevronDown");
export const IconChevronRight = wrap(NavArrowRight, "IconChevronRight");
export const IconChevronUp = wrap(NavArrowUp, "IconChevronUp");
export const IconClock = wrap(Clock, "IconClock");
export const IconCode = wrap(Code, "IconCode");
export const IconCoin = wrap(Coins, "IconCoin");
export const IconDownload = wrap(Download, "IconDownload");
export const IconFiles = wrap(MultiplePages, "IconFiles");
export const IconKey = wrap(Key, "IconKey");
export const IconLayoutDashboard = wrap(ViewGrid, "IconLayoutDashboard");
export const IconLogout = wrap(LogOut, "IconLogout");
export const IconMessageCircle = wrap(ChatBubble, "IconMessageCircle");
export const IconMoon = wrap(HalfMoon, "IconMoon");
export const IconReceipt = wrap(JournalPage, "IconReceipt");
export const IconRefresh = wrap(Refresh, "IconRefresh");
export const IconRepeat = wrap(Refresh, "IconRepeat");
export const IconReportMoney = wrap(Reports, "IconReportMoney");
export const IconPlus = wrap(Plus, "IconPlus");
export const IconSearch = wrap(Search, "IconSearch");
export const IconSelector = wrap(Sort, "IconSelector");
export const IconSettings = wrap(Settings, "IconSettings");
export const IconShield = wrap(Shield, "IconShield");
export const IconShieldCheck = wrap(ShieldCheck, "IconShieldCheck");
export const IconSitemap = wrap(Network, "IconSitemap");
export const IconSun = wrap(SunLight, "IconSun");
export const IconTransfer = wrap(DataTransferBoth, "IconTransfer");
export const IconUpload = wrap(Upload, "IconUpload");
export const IconUsers = wrap(Group, "IconUsers");
export const IconWallet = wrap(Wallet, "IconWallet");

// Used by dashboard quick-actions; kept for parity with prior tabler set.
export const IconDollar = wrap(Dollar, "IconDollar");
