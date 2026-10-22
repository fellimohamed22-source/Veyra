-- Invoices (owner decision 22/10/2026):
--  * RIDE: one invoice per completed ride, issued by VEYRA in the name and
--    on behalf of the driver (or of the driver's VTC company) to the
--    customer -- billing mandate; numbered per issuer.
--  * COMMISSION: one VEYRA invoice per driver and closed month for the
--    platform commission of that month's rides.
-- Seller, buyer and lines are snapshots: an issued invoice never changes.
-- VAT status of the issuer: NULL = not declared yet (no invoice issued).
-- Rollback : DROP TABLE invoices, invoice_sequences;
--            ALTER TABLE driver_companies DROP COLUMN vat_registered, DROP COLUMN vat_number;
--            ALTER TABLE vtc_companies DROP COLUMN vat_registered, DROP COLUMN vat_number;

ALTER TABLE driver_companies ADD COLUMN IF NOT EXISTS vat_registered BOOLEAN;
ALTER TABLE driver_companies ADD COLUMN IF NOT EXISTS vat_number VARCHAR(20);
ALTER TABLE vtc_companies ADD COLUMN IF NOT EXISTS vat_registered BOOLEAN;
ALTER TABLE vtc_companies ADD COLUMN IF NOT EXISTS vat_number VARCHAR(20);

CREATE TABLE invoice_sequences(
  issuer_key VARCHAR(64) NOT NULL,
  year INT NOT NULL,
  last_no INT NOT NULL,
  PRIMARY KEY(issuer_key, year)
);

CREATE TABLE invoices(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kind VARCHAR(16) NOT NULL,
  issuer_key VARCHAR(64) NOT NULL,
  number VARCHAR(40) NOT NULL,
  booking_id UUID UNIQUE REFERENCES scheduled_bookings(id),
  driver_id UUID NOT NULL REFERENCES drivers(id),
  period_start DATE,
  period_end DATE,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  seller JSONB NOT NULL,
  buyer JSONB NOT NULL,
  lines JSONB NOT NULL,
  vat_rate_bps INT NOT NULL,
  total_ht_minor BIGINT NOT NULL,
  vat_minor BIGINT NOT NULL,
  total_ttc_minor BIGINT NOT NULL,
  currency CHAR(3) NOT NULL,
  vat_mention TEXT,
  CONSTRAINT invoices_kind_chk CHECK (kind IN ('RIDE','COMMISSION')),
  CONSTRAINT invoices_total_chk CHECK (total_ttc_minor = total_ht_minor + vat_minor),
  CONSTRAINT invoices_number_uq UNIQUE(issuer_key, number)
);
CREATE UNIQUE INDEX ux_commission_invoice_month ON invoices(driver_id, period_start) WHERE kind='COMMISSION';
CREATE INDEX ix_invoices_driver ON invoices(driver_id, issued_at DESC);
