-- Double-entry accounting layer, missing from the MVP spec's requirement
-- (section 8 / complement 63): the CASH-debt and driver-payable subsystems
-- already track *what* is owed (driver_platform_debts, customer_platform_debts,
-- driver_payables), but nothing recorded the underlying accounting events
-- in a form that can be reconciled, audited, or summed into a trial balance.

CREATE TABLE IF NOT EXISTS ledger_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(64) NOT NULL UNIQUE,
  name VARCHAR(160) NOT NULL,
  type VARCHAR(16) NOT NULL CHECK (type IN ('ASSET','LIABILITY','REVENUE','EXPENSE')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ledger_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID REFERENCES scheduled_bookings(id),
  event_type VARCHAR(64) NOT NULL,
  description TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ledger_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id UUID NOT NULL REFERENCES ledger_transactions(id),
  account_id UUID NOT NULL REFERENCES ledger_accounts(id),
  direction VARCHAR(6) NOT NULL CHECK (direction IN ('DEBIT','CREDIT')),
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  currency CHAR(3) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_ledger_entries_transaction ON ledger_entries(transaction_id);
CREATE INDEX IF NOT EXISTS ix_ledger_entries_account ON ledger_entries(account_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_ledger_transactions_booking ON ledger_transactions(booking_id);

-- Chart of accounts -- only the accounts LedgerService actually posts to
-- (see LedgerService.java for the exact real events each one is used by).
INSERT INTO ledger_accounts (code, name, type) VALUES
  ('PLATFORM_REVENUE', 'Commission plateforme reconnue', 'REVENUE'),
  ('DRIVER_PAYABLE', 'Montants dus aux chauffeurs', 'LIABILITY'),
  ('DRIVER_PLATFORM_DEBT', 'Créances sur chauffeurs (commission CASH)', 'ASSET'),
  ('PAYMENT_PROCESSOR_CLEARING', 'Fonds captés via le PSP', 'ASSET'),
  ('PARTNER_RECEIVABLE', 'Créances sur partenaires (facturation différée)', 'ASSET'),
  ('CASH_ON_HAND', 'Espèces reçues (règlement de dette)', 'ASSET')
ON CONFLICT (code) DO NOTHING;
