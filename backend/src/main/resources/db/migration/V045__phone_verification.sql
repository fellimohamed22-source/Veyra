-- V4 L11 (DEC-07, CL-AUTH-05) : numéro de téléphone vérifié par OTP
-- (Firebase Phone Auth). Un numéro vérifié n'appartient qu'à un compte.
-- Rollback : DROP INDEX IF EXISTS ux_users_verified_phone; ALTER TABLE users DROP COLUMN phone_verified_at;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_verified_at TIMESTAMPTZ;
CREATE UNIQUE INDEX IF NOT EXISTS ux_users_verified_phone ON users(phone) WHERE phone_verified_at IS NOT NULL;
