-- Mode "meilleure offre visible" vs "offre privée" (voir docs métier
-- fournies) : suit exactement le même pattern que
-- commission_policy_versions (table déjà existante, versionnée,
-- auditable) plutôt qu'un simple flag global, pour permettre l'historique
-- et la cohérence avec le reste des réglages admin.
CREATE TABLE offer_visibility_policy_versions(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mode VARCHAR(20) NOT NULL CHECK (mode IN ('PRIVATE','BEST_VISIBLE')),
  version_no INT NOT NULL,
  status VARCHAR(20) NOT NULL,
  effective_from TIMESTAMPTZ,
  effective_to TIMESTAMPTZ
);
INSERT INTO offer_visibility_policy_versions(mode,version_no,status,effective_from)
VALUES ('PRIVATE',1,'ACTIVE',now());

-- Snapshotté à la CRÉATION de la réservation (pas relu dynamiquement),
-- pour la même raison que commission_bps est snapshotté dans
-- booking_financial_snapshots : si l'admin change le réglage global
-- pendant qu'une enchère est déjà ouverte, les chauffeurs déjà invités
-- ne doivent pas voir les règles du jeu changer en cours de route.
ALTER TABLE scheduled_bookings ADD COLUMN IF NOT EXISTS offer_visibility_mode VARCHAR(20) NOT NULL DEFAULT 'PRIVATE' CHECK (offer_visibility_mode IN ('PRIVATE','BEST_VISIBLE'));
