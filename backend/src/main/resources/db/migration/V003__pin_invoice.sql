ALTER TABLE scheduled_bookings ADD COLUMN pin_encrypted TEXT;
CREATE TABLE partner_invoice_items(id UUID PRIMARY KEY DEFAULT gen_random_uuid(),invoice_id UUID NOT NULL REFERENCES partner_invoices(id),booking_id UUID NOT NULL UNIQUE REFERENCES scheduled_bookings(id),driver_net_minor BIGINT NOT NULL,commission_minor BIGINT NOT NULL,tax_minor BIGINT NOT NULL DEFAULT 0,total_minor BIGINT NOT NULL);
