ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS attempt_count INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_error VARCHAR(500);

CREATE INDEX IF NOT EXISTS ix_notifications_delivery
  ON notifications(status,next_attempt_at,scheduled_for,created_at)
  WHERE status='PENDING';
