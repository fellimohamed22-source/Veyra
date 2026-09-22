CREATE TABLE customer_saved_addresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label VARCHAR(80) NOT NULL,
  address TEXT NOT NULL,
  lat DOUBLE PRECISION NOT NULL CHECK(lat BETWEEN -90 AND 90),
  lng DOUBLE PRECISION NOT NULL CHECK(lng BETWEEN -180 AND 180),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_saved_addresses_user ON customer_saved_addresses(user_id);
CREATE TABLE customer_favorite_drivers (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  booking_id UUID NOT NULL REFERENCES scheduled_bookings(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id,driver_id)
);

ALTER TABLE scheduled_bookings ADD COLUMN preferred_driver_id UUID REFERENCES drivers(id);

CREATE TABLE booking_creation_requests (
  user_id UUID NOT NULL REFERENCES users(id), request_key VARCHAR(128) NOT NULL,
  request_body TEXT NOT NULL, booking_id UUID NOT NULL REFERENCES scheduled_bookings(id),
  PRIMARY KEY(user_id,request_key)
);
