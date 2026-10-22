-- Owner decision 22/10/2026: one person may hold a client account AND a
-- driver account with the same e-mail, but a client account cannot sign in
-- to the driver app and vice versa. Each account gets a type; e-mail, Firebase
-- identity and verified phone become unique per type. Web portal accounts
-- (partners, VTC companies, staff) are CLIENT-type accounts.
-- Existing users with a driver profile become DRIVER accounts; the others
-- CLIENT. A person who used both apps with one account keeps it in the driver
-- app and can create a separate client account with the same e-mail.
-- Rollback : DROP INDEX ux_users_email_account_type; ALTER TABLE users ADD CONSTRAINT users_email_key UNIQUE(email);
--            (requires removing duplicate e-mails first) ; ALTER TABLE users DROP COLUMN account_type;

ALTER TABLE users ADD COLUMN IF NOT EXISTS account_type VARCHAR(12) NOT NULL DEFAULT 'CLIENT';
ALTER TABLE users ADD CONSTRAINT users_account_type_chk CHECK (account_type IN ('CLIENT','DRIVER'));
UPDATE users u SET account_type='DRIVER' WHERE EXISTS (SELECT 1 FROM drivers d WHERE d.user_id=u.id);

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_email_key;
CREATE UNIQUE INDEX IF NOT EXISTS ux_users_email_account_type ON users(email, account_type);

DROP INDEX IF EXISTS ux_users_firebase_uid;
CREATE UNIQUE INDEX ux_users_firebase_uid ON users(firebase_uid, account_type) WHERE firebase_uid IS NOT NULL;

DROP INDEX IF EXISTS ux_users_verified_phone;
CREATE UNIQUE INDEX ux_users_verified_phone ON users(phone, account_type) WHERE phone_verified_at IS NOT NULL;
