-- Driver payouts by bank transfer (owner request 22/10/2026, as Uber and
-- Bolt require a RIB): account holder, IBAN encrypted at rest (AES-GCM,
-- same key as the ride PINs), last four digits kept in clear for display,
-- optional BIC. The RIB document itself is a driver_documents row (RIB).
-- Rollback : DROP TABLE driver_bank_accounts;
CREATE TABLE driver_bank_accounts(
  driver_id UUID PRIMARY KEY REFERENCES drivers(id),
  holder_name VARCHAR(140) NOT NULL,
  iban_encrypted TEXT NOT NULL,
  iban_country CHAR(2) NOT NULL,
  iban_last4 VARCHAR(4) NOT NULL,
  bic VARCHAR(11),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
