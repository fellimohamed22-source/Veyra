-- V4 L12 (PART-13, PART-03) : lien de suivi pour le passager d'une
-- réservation partenaire, sans compte. Seul le hash SHA-256 du jeton est
-- stocké ; le jeton en clair n'est montré qu'une fois à sa création.
-- Un lien expire (ride.guest_link_hours_after_pickup après l'heure de
-- prise en charge) et peut être révoqué.
-- Rollback : DROP TABLE guest_access_links; DELETE FROM platform_settings WHERE setting_key='guest.link_hours_after_pickup';
CREATE TABLE guest_access_links(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES scheduled_bookings(id),
  token_hash CHAR(64) NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_guest_links_booking ON guest_access_links(booking_id) WHERE revoked_at IS NULL;

INSERT INTO platform_settings(setting_key,value_number,min_value,max_value,description) VALUES
 ('guest.link_hours_after_pickup',24,1,168,'Durée de validité du lien passager après l''heure de prise en charge')
ON CONFLICT (setting_key) DO NOTHING;
