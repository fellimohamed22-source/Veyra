CREATE TABLE IF NOT EXISTS kyc_reviews(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  reviewer_id UUID REFERENCES users(id),
  decision VARCHAR(24) NOT NULL,
  reason_code VARCHAR(64),
  comment TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_kyc_reviews_driver ON kyc_reviews(driver_id,created_at DESC);
