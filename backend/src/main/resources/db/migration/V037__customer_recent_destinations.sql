-- Recent destinations are explicitly recorded by the customer; no automatic GPS tracking.
-- Keep only the 20 most recent per user; expire unused entries after 90 days.
CREATE TABLE customer_recent_destinations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  address VARCHAR(500) NOT NULL,
  lat DOUBLE PRECISION NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lng DOUBLE PRECISION NOT NULL CHECK (lng BETWEEN -180 AND 180),
  last_used_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_customer_recent_destinations_user_time ON customer_recent_destinations(user_id,last_used_at DESC);
