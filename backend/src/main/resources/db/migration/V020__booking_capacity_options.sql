ALTER TABLE scheduled_bookings
  ADD COLUMN IF NOT EXISTS passenger_count SMALLINT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS baggage_count SMALLINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS customer_notes VARCHAR(1000);

ALTER TABLE scheduled_bookings
  ADD CONSTRAINT chk_booking_passengers CHECK (passenger_count BETWEEN 1 AND 9),
  ADD CONSTRAINT chk_booking_baggage CHECK (baggage_count BETWEEN 0 AND 12);

CREATE INDEX IF NOT EXISTS ix_booking_category_schedule
  ON scheduled_bookings(category_id,scheduled_at,status);
