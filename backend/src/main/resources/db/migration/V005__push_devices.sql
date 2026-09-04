CREATE TABLE IF NOT EXISTS user_devices(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform VARCHAR(20) NOT NULL,
  push_token VARCHAR(512) NOT NULL,
  device_name VARCHAR(255),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_user_devices_token ON user_devices(push_token);
CREATE INDEX IF NOT EXISTS ix_user_devices_user_active ON user_devices(user_id,active);
