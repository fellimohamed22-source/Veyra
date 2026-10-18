-- V4 CL-18 (planche 16) : état lu / non lu des notifications in-app.
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS ix_notifications_unread ON notifications(user_id) WHERE read_at IS NULL;
