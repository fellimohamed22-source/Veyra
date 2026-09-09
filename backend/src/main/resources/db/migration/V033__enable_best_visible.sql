-- Real fix: a previous commit edited V032 directly to flip the seeded
-- default from PRIVATE to BEST_VISIBLE -- editing an already-applied
-- Flyway migration changes its checksum, which Flyway detects as
-- corruption and refuses to start against by default on any deploy
-- that already recorded V032's original checksum. V032 has been
-- reverted to its original, already-applied content; this migration
-- makes the same real change (activate BEST_VISIBLE) the correct way:
-- a new version, matching how offer_visibility_policy_versions is
-- actually meant to be updated (see ConfigController.updateOfferVisibility,
-- the same INACTIVATE-then-INSERT pattern used any time an admin
-- changes this policy through the API).
UPDATE offer_visibility_policy_versions SET status='INACTIVE',effective_to=now() WHERE status='ACTIVE';
INSERT INTO offer_visibility_policy_versions(mode,version_no,status,effective_from)
VALUES ('BEST_VISIBLE',2,'ACTIVE',now());
