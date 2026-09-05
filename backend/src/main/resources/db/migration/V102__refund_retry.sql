ALTER TABLE refunds
  ADD COLUMN IF NOT EXISTS attempt_count INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS ix_refunds_retry
  ON refunds(status,next_attempt_at,created_at)
  WHERE status='REQUESTED';
