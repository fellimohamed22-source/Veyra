CREATE TABLE IF NOT EXISTS refunds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id UUID NOT NULL REFERENCES payments(id),
  booking_id UUID NOT NULL REFERENCES scheduled_bookings(id),
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  currency CHAR(3) NOT NULL,
  provider VARCHAR(32) NOT NULL,
  provider_ref VARCHAR(255),
  status VARCHAR(24) NOT NULL DEFAULT 'REQUESTED',
  failure_message VARCHAR(500),
  idempotency_key VARCHAR(128) NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_refunds_status_created
  ON refunds(status,created_at);
