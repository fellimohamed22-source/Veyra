-- MeController.java selects users.locale and users.timezone, but
-- neither column has ever existed (V001 didn't include them, and no
-- later migration added them either -- confirmed by grepping the full
-- migration history). Every call to GET /api/v1/me has been failing
-- with "column locale does not exist" since that endpoint was written.
-- Defaults: 'fr' matches the app's French-first UI copy (see
-- app_locale.dart's fallback-to-French behavior); 'Europe/Paris'
-- matches the initial market (Saint-Tropez / French Riviera).
ALTER TABLE users ADD COLUMN IF NOT EXISTS locale VARCHAR(10) NOT NULL DEFAULT 'fr';
ALTER TABLE users ADD COLUMN IF NOT EXISTS timezone VARCHAR(64) NOT NULL DEFAULT 'Europe/Paris';
