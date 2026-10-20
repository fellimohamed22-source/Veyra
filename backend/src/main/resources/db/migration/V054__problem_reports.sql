-- « Signaler un problème » (board 10 P4): a ride participant reports an
-- issue; the support team sees and closes it.
-- Rollback : DROP TABLE problem_reports;
CREATE TABLE problem_reports(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES scheduled_bookings(id),
  reporter_user_id UUID NOT NULL REFERENCES users(id),
  category VARCHAR(32) NOT NULL,
  message VARCHAR(1000),
  status VARCHAR(16) NOT NULL DEFAULT 'OPEN',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES users(id),
  CONSTRAINT problem_reports_category_chk CHECK (category IN ('DRIVER_LATE','DRIVER_NOT_FOUND','SAFETY','VEHICLE','ROUTE','PAYMENT','OTHER')),
  CONSTRAINT problem_reports_status_chk CHECK (status IN ('OPEN','RESOLVED'))
);
CREATE INDEX problem_reports_open_idx ON problem_reports(created_at) WHERE status='OPEN';
