-- Explicitly selected destinations only; no passive GPS tracking.
CREATE TABLE customer_recent_destinations (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 address VARCHAR(500) NOT NULL,
 lat DOUBLE PRECISION NOT NULL CHECK(lat BETWEEN -90 AND 90),
 lng DOUBLE PRECISION NOT NULL CHECK(lng BETWEEN -180 AND 180),
 last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CONSTRAINT uq_customer_recent_destination UNIQUE(user_id,address,lat,lng)
);
CREATE INDEX ix_customer_recent_destinations_user_time ON customer_recent_destinations(user_id,last_used_at DESC);
