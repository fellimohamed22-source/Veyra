-- V4 L6 : moteur de commission configurable en base (DEC-01 méthode A,
-- DEC-02 barème en base, DEC-03 fixe/plancher/plafond en base).
--
-- Étend la table existante commission_policy_versions (pas de doublon).
-- Portées, de la plus prioritaire à la moins prioritaire :
--   USER             exception pour un client particulier (réservations CLIENT)
--   PARTNER          exception pour une organisation partenaire
--   PARTNER_CATEGORY catégorie partenaire (HOTEL, CONCIERGE, ...) = partner_type
--   PROFILE          profil du réservataire : CLIENT ou PARTNER
--   STANDARD         règle générale
-- Méthode A : commission = arrondi(prix chauffeur × bps / 10000) + fixe,
-- bornée par [plancher, plafond] ; prix client = prix chauffeur + commission.
-- Une version n'est jamais modifiée après création (seuls status et
-- effective_to évoluent) : les offres référencent leur version figée.
--
-- Rollback : DELETE FROM commission_policy_versions WHERE scope_type IN ('USER','PARTNER_CATEGORY','PROFILE');
--   ALTER TABLE commission_policy_versions DROP CONSTRAINT ck_commission_scope_subject,
--   DROP CONSTRAINT ck_commission_bounds, DROP COLUMN user_id, DROP COLUMN profile_type,
--   DROP COLUMN partner_category, DROP COLUMN fixed_minor, DROP COLUMN min_commission_minor,
--   DROP COLUMN max_commission_minor, DROP COLUMN currency, DROP COLUMN created_by,
--   DROP COLUMN justification, DROP COLUMN created_at;
ALTER TABLE commission_policy_versions
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS profile_type VARCHAR(16),
  ADD COLUMN IF NOT EXISTS partner_category VARCHAR(40),
  ADD COLUMN IF NOT EXISTS fixed_minor BIGINT NOT NULL DEFAULT 0 CHECK (fixed_minor>=0),
  ADD COLUMN IF NOT EXISTS min_commission_minor BIGINT CHECK (min_commission_minor>=0),
  ADD COLUMN IF NOT EXISTS max_commission_minor BIGINT CHECK (max_commission_minor>=0),
  ADD COLUMN IF NOT EXISTS currency CHAR(3) NOT NULL DEFAULT 'EUR',
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS justification VARCHAR(500),
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE commission_policy_versions ADD CONSTRAINT ck_commission_scope_subject CHECK (
  (scope_type='STANDARD' AND partner_id IS NULL AND user_id IS NULL AND profile_type IS NULL AND partner_category IS NULL)
  OR (scope_type='PROFILE' AND profile_type IN ('CLIENT','PARTNER') AND partner_id IS NULL AND user_id IS NULL AND partner_category IS NULL)
  OR (scope_type='PARTNER_CATEGORY' AND partner_category IS NOT NULL AND partner_id IS NULL AND user_id IS NULL AND profile_type IS NULL)
  OR (scope_type='PARTNER' AND partner_id IS NOT NULL AND user_id IS NULL AND profile_type IS NULL AND partner_category IS NULL)
  OR (scope_type='USER' AND user_id IS NOT NULL AND partner_id IS NULL AND profile_type IS NULL AND partner_category IS NULL));

ALTER TABLE commission_policy_versions ADD CONSTRAINT ck_commission_bounds CHECK (
  min_commission_minor IS NULL OR max_commission_minor IS NULL OR min_commission_minor<=max_commission_minor);

CREATE INDEX IF NOT EXISTS ix_commission_active_scope
  ON commission_policy_versions(scope_type,status,effective_from);

-- Barème initial (DEC-02) : reprend les taux V3, désormais en base.
-- Profil PARTNER à 600 bps : remplace la règle 600 bps qui était créée en
-- dur pour chaque organisation (les règles PARTNER déjà créées restent
-- valides et équivalentes ; l'admin peut les désactiver).
INSERT INTO commission_policy_versions(id,scope_type,profile_type,commission_bps,version_no,status,effective_from,justification)
SELECT gen_random_uuid(),'PROFILE','PARTNER',600,1,'ACTIVE',now(),'Barème initial V4 (reprise du taux partenaire V3)'
WHERE NOT EXISTS (SELECT 1 FROM commission_policy_versions WHERE scope_type='PROFILE' AND profile_type='PARTNER');
