-- V4 (DR-AUTH-01..09, planche 08 B) : détails du dossier chauffeur
-- demandés par le parcours d'inscription en 7 étapes. Toutes les colonnes
-- sont facultatives pour ne pas casser les dossiers existants.
ALTER TABLE drivers ADD COLUMN IF NOT EXISTS birth_date DATE;
ALTER TABLE drivers ADD COLUMN IF NOT EXISTS driver_type VARCHAR(16) NOT NULL DEFAULT 'INDEPENDENT';
ALTER TABLE drivers ADD CONSTRAINT drivers_type_chk CHECK (driver_type IN ('INDEPENDENT','AFFILIATED'));

-- Recto / verso et nature de la pièce d'identité (carte, passeport, titre de séjour).
ALTER TABLE driver_documents ADD COLUMN IF NOT EXISTS side VARCHAR(8);
ALTER TABLE driver_documents ADD COLUMN IF NOT EXISTS subtype VARCHAR(32);
ALTER TABLE driver_documents ADD CONSTRAINT driver_documents_side_chk CHECK (side IS NULL OR side IN ('FRONT','BACK'));

ALTER TABLE driver_companies ADD COLUMN IF NOT EXISTS legal_form VARCHAR(40);
ALTER TABLE driver_companies ADD COLUMN IF NOT EXISTS address VARCHAR(255);

-- Places et bagages déclarés (éligibilité « places/bagages compatibles »).
ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS seats SMALLINT;
ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS baggage_capacity SMALLINT;
ALTER TABLE vehicles ADD CONSTRAINT vehicles_seats_chk CHECK (seats IS NULL OR seats BETWEEN 1 AND 9);
ALTER TABLE vehicles ADD CONSTRAINT vehicles_baggage_chk CHECK (baggage_capacity IS NULL OR baggage_capacity BETWEEN 0 AND 20);

CREATE TABLE IF NOT EXISTS driver_licenses(
  driver_id UUID PRIMARY KEY REFERENCES drivers(id),
  license_number VARCHAR(40) NOT NULL,
  category VARCHAR(8) NOT NULL,
  expires_at DATE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
