-- Owner decision 22/10/2026: no geographic restriction for now on new
-- requests (the pilot zone « Sud de la France, Marseille - Menton » is
-- paused). Booking creation only checks the pickup point when an ACTIVE
-- zone version exists, so pausing the zone lifts the restriction without
-- code change. To restore or change it later: insert a new ACTIVE version
-- (or set this one back to 'ACTIVE').
-- Rollback : UPDATE service_zone_versions SET status='ACTIVE' WHERE status='PAUSED';
UPDATE service_zone_versions SET status='PAUSED' WHERE status='ACTIVE';
