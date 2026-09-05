CREATE TABLE IF NOT EXISTS driver_quality_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES drivers(id),
  booking_id UUID REFERENCES scheduled_bookings(id),
  event_type VARCHAR(64) NOT NULL,
  severity SMALLINT NOT NULL DEFAULT 1 CHECK (severity BETWEEN 1 AND 5),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_driver_quality_events_driver
  ON driver_quality_events(driver_id,created_at DESC);
