-- TEST ACCOUNTS -- pilot/dev only, not for production data.
-- Passwords hashed with BCrypt cost 12 (same cost as SecurityConfig.encoder()).
--   client@test.com   / Client@12345.
--   chauffeur@test.com / Chauffeur@12345.
-- ON CONFLICT DO NOTHING so this migration is a no-op if these emails
-- already exist (re-running the pipeline, or accounts created manually
-- in the meantime).

INSERT INTO users(id,first_name,last_name,email,password_hash,status,email_verified_at)
VALUES (
  gen_random_uuid(),'Client','Test','client@test.com',
  '$2b$12$4gP7mzS/hoQ4Xq7PC158ceai9Wl/QTto1t5nAZqbORHla9WCOboUO',
  'ACTIVE', now()
) ON CONFLICT (email) DO NOTHING;

INSERT INTO users(id,first_name,last_name,email,password_hash,status,email_verified_at)
VALUES (
  gen_random_uuid(),'Chauffeur','Test','chauffeur@test.com',
  '$2b$12$SkR23jyR/x3rOYjhw/MR4OMlmskDr9g3KZU5Ghm6IT0u1iwi6SXiW',
  'ACTIVE', now()
) ON CONFLICT (email) DO NOTHING;

INSERT INTO user_roles(user_id,role_id)
SELECT u.id, r.id FROM users u, roles r
WHERE u.email='client@test.com' AND r.code='CLIENT'
ON CONFLICT DO NOTHING;

INSERT INTO user_roles(user_id,role_id)
SELECT u.id, r.id FROM users u, roles r
WHERE u.email='chauffeur@test.com' AND r.code='DRIVER'
ON CONFLICT DO NOTHING;

-- Minimal driver profile row so the DRIVER-role account can actually
-- authenticate against driver-scoped endpoints. This does NOT create a
-- vehicle or documents: the real matching/eligibility rules (see
-- CORE_MARKETPLACE spec, section "DRIVER MATCHING") still require valid
-- documents + a vehicle before this driver can receive real booking
-- invitations. marketplace_enabled left FALSE (the real default) on
-- purpose -- flipping it here would silently bypass the KYC gate the
-- business rules require.
INSERT INTO drivers(id,user_id,status,kyc_status,marketplace_enabled)
SELECT gen_random_uuid(), u.id, 'PENDING_KYC', 'DRAFT', FALSE
FROM users u WHERE u.email='chauffeur@test.com'
ON CONFLICT (user_id) DO NOTHING;
