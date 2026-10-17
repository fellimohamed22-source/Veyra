-- V4 L0-SEC : liaison explicite entre un compte VEYRA et une identité
-- Firebase (claim "sub"/"user_id"). Avant cette migration, /auth/firebase
-- retrouvait le compte uniquement par email ou téléphone, sans vérifier
-- que l'email était confirmé, ce qui permettait une prise de contrôle de
-- compte. La colonne est nullable : les comptes existants se lient à la
-- première connexion Firebase dont l'email est vérifié.
-- Rollback : ALTER TABLE users DROP COLUMN firebase_uid;
ALTER TABLE users ADD COLUMN IF NOT EXISTS firebase_uid VARCHAR(128);
CREATE UNIQUE INDEX IF NOT EXISTS ux_users_firebase_uid ON users(firebase_uid) WHERE firebase_uid IS NOT NULL;
