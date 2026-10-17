-- V4 L2 : la commission est figée sur chaque offre au moment de sa
-- soumission (cahier des charges §07 : "Changement de taux n'altère jamais
-- une offre déjà publiée"). Avant, le total client était recalculé à chaque
-- lecture avec le taux ACTIF du moment, puis figé seulement à l'acceptation.
--
-- La formule reste celle de V3 (prix chauffeur + commission sur prix
-- chauffeur, arrondi HALF_UP) : cette migration ne tranche PAS l'arbitrage
-- méthode A/B (DEC-01), elle fige seulement la règle en vigueur.
--
-- Colonnes nullables avec contrainte tout-ou-rien : les lignes NULL sont
-- des offres héritées que le code recalcule ; toutes les offres existantes
-- sont rattrapées ci-dessous.
-- Rollback : ALTER TABLE driver_offers DROP CONSTRAINT ck_driver_offers_commission_snapshot,
--   DROP COLUMN commission_policy_id, DROP COLUMN commission_rate_bps,
--   DROP COLUMN commission_minor, DROP COLUMN customer_total_minor;
ALTER TABLE driver_offers
  ADD COLUMN IF NOT EXISTS commission_policy_id UUID REFERENCES commission_policy_versions(id),
  ADD COLUMN IF NOT EXISTS commission_rate_bps INT,
  ADD COLUMN IF NOT EXISTS commission_minor BIGINT,
  ADD COLUMN IF NOT EXISTS customer_total_minor BIGINT;

UPDATE driver_offers o
SET commission_policy_id=p.id,
    commission_rate_bps=p.commission_bps,
    commission_minor=round(o.proposed_amount_minor::numeric*p.commission_bps/10000),
    customer_total_minor=o.proposed_amount_minor+round(o.proposed_amount_minor::numeric*p.commission_bps/10000)
FROM scheduled_bookings sb,
LATERAL (
  SELECT cp.id,cp.commission_bps FROM commission_policy_versions cp
  WHERE cp.status='ACTIVE' AND ((cp.scope_type='PARTNER' AND cp.partner_id=sb.partner_id) OR cp.scope_type='STANDARD')
  ORDER BY CASE WHEN cp.scope_type='PARTNER' THEN 0 ELSE 1 END, cp.version_no DESC
  LIMIT 1
) p
WHERE sb.id=o.booking_id AND o.commission_minor IS NULL;

-- Offres déjà acceptées : la valeur de référence est celle du snapshot de
-- réservation, pas le taux actif actuel.
UPDATE driver_offers o
SET commission_policy_id=bfs.commission_policy_id,
    commission_rate_bps=bfs.commission_rate_bps,
    commission_minor=bfs.platform_commission_amount_minor,
    customer_total_minor=bfs.customer_total_amount_minor
FROM booking_financial_snapshots bfs
WHERE bfs.offer_id=o.id;

ALTER TABLE driver_offers ADD CONSTRAINT ck_driver_offers_commission_snapshot CHECK (
  (commission_policy_id IS NULL AND commission_rate_bps IS NULL AND commission_minor IS NULL AND customer_total_minor IS NULL)
  OR (commission_policy_id IS NOT NULL AND commission_rate_bps BETWEEN 0 AND 10000 AND commission_minor>=0
      AND customer_total_minor=proposed_amount_minor+commission_minor));
