ALTER TABLE scheduled_bookings
  ADD COLUMN IF NOT EXISTS pin_failed_attempts INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS pin_locked_until TIMESTAMPTZ;

ALTER TABLE scheduled_bookings
  ADD CONSTRAINT chk_pin_failed_attempts_nonnegative CHECK (pin_failed_attempts >= 0);
