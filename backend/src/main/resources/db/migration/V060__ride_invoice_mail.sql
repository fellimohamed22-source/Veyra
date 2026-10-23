-- Ride invoice e-mailed to the customer once the ride is completed (owner
-- decision 22/10/2026). One row per ride: retried with a growing delay
-- (e.g. while the driver's VAT status is missing), at most 48 attempts.
-- Rollback : DROP TABLE ride_invoice_mails;
CREATE TABLE ride_invoice_mails(
  booking_id UUID PRIMARY KEY REFERENCES scheduled_bookings(id),
  attempts INT NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_error VARCHAR(80),
  sent_at TIMESTAMPTZ
);
