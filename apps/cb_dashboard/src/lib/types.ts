export interface AuthUser {
  user_id: string;
  email: string;
  role: string;
  status: string;
}

export interface Party {
  party_id: string;
  full_name: string;
  email: string;
  status: string;
  created_at: number;
  updated_at: number;
}

export interface Account {
  account_id: string;
  party_id: string;
  name: string;
  currency: string;
  balance: number;
  status: string;
  created_at: number;
  updated_at: number;
}

export interface Transaction {
  txn_id: string;
  idempotency_key: string;
  txn_type: string;
  status: string;
  amount: number;
  currency: string;
  source_account_id: string;
  dest_account_id: string;
  description: string;
  created_at: number;
  posted_at: number;
}

export interface LedgerEntry {
  entry_id: string;
  txn_id: string;
  account_id: string;
  entry_type: string;
  amount: number;
  currency: string;
  description: string;
  posted_at: number;
}

export interface SavingsProduct {
  product_id: string;
  name: string;
  description: string;
  currency: string;
  interest_rate_bps: number;
  interest_type: string;
  compounding_period: string;
  minimum_balance: number;
  status: string;
  created_at: number;
  updated_at: number;
}

export interface LoanProduct {
  product_id: string;
  name: string;
  description: string;
  currency: string;
  min_amount: number;
  max_amount: number;
  min_term_months: number;
  max_term_months: number;
  interest_rate_bps: number;
  interest_type: string;
  status: string;
  created_at: number;
  updated_at: number;
}

export interface Loan {
  loan_id: string;
  product_id: string;
  party_id: string;
  account_id: string;
  principal: number;
  currency: string;
  interest_rate_bps: number;
  term_months: number;
  monthly_payment: number;
  outstanding_balance: number;
  status: string;
  disbursed_at: number;
  created_at: number;
  updated_at: number;
}

export interface LoanRepayment {
  repayment_id: string;
  loan_id: string;
  amount: number;
  principal_portion: number;
  interest_portion: number;
  penalty: number;
  due_date: number;
  paid_at: number;
  status: string;
  created_at: number;
}

export interface BalanceResponse {
  account_id: string;
  currency: string;
  balance: number;
  available_balance: number;
  balance_formatted: string;
}

export interface AccountHold {
  hold_id: string;
  account_id: string;
  amount: number;
  reason: string;
  status: string;
  placed_at: number;
  released_at: number;
  expires_at: number;
}

export interface DashboardStats {
  total_customers: number;
  total_accounts: number;
  total_balance: number;
  today_txns: number;
  pending_txns: number;
}

export interface ActivityItem {
  id: string;
  type: string;
  description: string;
  timestamp: number;
  amount: number;
  currency: string;
}

export interface PaymentOrder {
  payment_id: string;
  idempotency_key: string;
  party_id: string;
  source_account_id: string;
  dest_account_id: string;
  amount: number;
  currency: string;
  description: string;
  status: string;
  stp_decision: string;
  failure_reason: string;
  retry_count: number;
  created_at: number;
  updated_at: number;
}

export interface ExceptionItem {
  item_id: string;
  payment_id: string;
  reason: string;
  status: string;
  resolution: string;
  resolved_by: string;
  resolution_notes: string;
  created_at: number;
  updated_at: number;
}

export interface ChannelLimit {
  channel_type: string;
  currency: string;
  daily_limit: number;
  per_txn_limit: number;
  updated_at: number;
}

export interface ChannelActivity {
  log_id: string;
  channel: string;
  party_id: string | null;
  action: string;
  endpoint: string;
  status_code: number;
  created_at: number;
}
