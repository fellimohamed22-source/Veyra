-- V4 (planches 13 P4 / 14 P2) : véhicule présenté avec l'offre et message
-- facultatif au client (200 caractères, sans coordonnées : CL-15).
ALTER TABLE driver_offers ADD COLUMN IF NOT EXISTS vehicle_id UUID REFERENCES vehicles(id);
ALTER TABLE driver_offers ADD COLUMN IF NOT EXISTS message VARCHAR(200);
