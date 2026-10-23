-- Owner report 23/10/2026: client2@test.com is a client account, but V058
-- made it a DRIVER account because a driver profile had been created on it
-- (the account had been used in the driver app). Same correction for
-- client@test.com. The stray driver profile is removed when it has no
-- history; otherwise it is kept, detached from any login (a client account
-- never opens the driver app).
-- Rollback : UPDATE users SET account_type='DRIVER' WHERE email IN ('client@test.com','client2@test.com');

UPDATE users u SET account_type='CLIENT', updated_at=now()
WHERE u.email IN ('client@test.com','client2@test.com') AND u.account_type='DRIVER'
  AND NOT EXISTS (SELECT 1 FROM users c WHERE c.email=u.email AND c.account_type='CLIENT');

DELETE FROM user_roles ur USING users u, roles r
WHERE ur.user_id=u.id AND ur.role_id=r.id AND r.code='DRIVER'
  AND u.email IN ('client@test.com','client2@test.com') AND u.account_type='CLIENT';

INSERT INTO user_roles(user_id,role_id)
SELECT u.id, r.id FROM users u, roles r
WHERE u.email IN ('client@test.com','client2@test.com') AND u.account_type='CLIENT' AND r.code='CLIENT'
ON CONFLICT DO NOTHING;

DO $$
DECLARE d RECORD;
BEGIN
  FOR d IN SELECT dr.id FROM drivers dr JOIN users u ON u.id=dr.user_id
           WHERE u.email IN ('client@test.com','client2@test.com') AND u.account_type='CLIENT' LOOP
    BEGIN
      DELETE FROM drivers WHERE id=d.id;
    EXCEPTION WHEN foreign_key_violation THEN
      NULL; -- the profile has history (documents, offers...): kept, unreachable.
    END;
  END LOOP;
END $$;
