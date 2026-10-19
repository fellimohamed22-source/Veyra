-- V4 portail partenaire (maquette validée DEC-13) : référence interne
-- de l'établissement (dossier, chambre). Visible du partenaire seulement.
-- Rollback : ALTER TABLE scheduled_bookings DROP COLUMN partner_reference;
ALTER TABLE scheduled_bookings ADD COLUMN IF NOT EXISTS partner_reference VARCHAR(100);
