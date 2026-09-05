ALTER TABLE cancellation_policy_versions
  ADD COLUMN IF NOT EXISTS driver_share_mid_bps INTEGER NOT NULL DEFAULT 7000,
  ADD COLUMN IF NOT EXISTS driver_share_late_bps INTEGER NOT NULL DEFAULT 8000,
  ADD COLUMN IF NOT EXISTS driver_share_no_show_bps INTEGER NOT NULL DEFAULT 8000;

ALTER TABLE cancellation_policy_versions
  ADD CONSTRAINT chk_driver_share_mid CHECK (driver_share_mid_bps BETWEEN 0 AND 10000),
  ADD CONSTRAINT chk_driver_share_late CHECK (driver_share_late_bps BETWEEN 0 AND 10000),
  ADD CONSTRAINT chk_driver_share_no_show CHECK (driver_share_no_show_bps BETWEEN 0 AND 10000);
