ALTER TABLE cancellation_policy_versions
  ADD COLUMN IF NOT EXISTS mid_fee_min_minor BIGINT NOT NULL DEFAULT 500,
  ADD COLUMN IF NOT EXISTS no_show_cap_minor BIGINT NOT NULL DEFAULT 10000;

ALTER TABLE cancellation_policy_versions
  ADD CONSTRAINT chk_mid_fee_min_nonnegative CHECK (mid_fee_min_minor >= 0),
  ADD CONSTRAINT chk_no_show_cap_positive CHECK (no_show_cap_minor > 0);
