CREATE TABLE IF NOT EXISTS customer_platform_debts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id),
  driver_id UUID REFERENCES drivers(id),
  booking_id UUID NOT NULL UNIQUE REFERENCES scheduled_bookings(id),
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  paid_amount_minor BIGINT NOT NULL DEFAULT 0 CHECK (paid_amount_minor >= 0),
  driver_compensation_minor BIGINT NOT NULL DEFAULT 0 CHECK (driver_compensation_minor >= 0),
  platform_amount_minor BIGINT NOT NULL DEFAULT 0 CHECK (platform_amount_minor >= 0),
  currency CHAR(3) NOT NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'DUE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_customer_debts_user_status
  ON customer_platform_debts(user_id,status,created_at DESC);
