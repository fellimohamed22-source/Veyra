CREATE OR REPLACE FUNCTION veyra_record_booking_status_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO booking_status_history(
      booking_id,from_status,to_status,actor_type,actor_id,reason_code,created_at)
    VALUES (
      NEW.id,NULL,NEW.status,'SYSTEM',NULL,NULL,coalesce(NEW.created_at,now()));
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO booking_status_history(
      booking_id,from_status,to_status,actor_type,actor_id,reason_code,created_at)
    VALUES (
      NEW.id,OLD.status,NEW.status,'SYSTEM',NULL,NULL,now());
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_scheduled_bookings_status_history ON scheduled_bookings;

CREATE TRIGGER trg_scheduled_bookings_status_history
AFTER INSERT OR UPDATE OF status ON scheduled_bookings
FOR EACH ROW
EXECUTE FUNCTION veyra_record_booking_status_change();

INSERT INTO booking_status_history(
  booking_id,from_status,to_status,actor_type,actor_id,reason_code,created_at)
SELECT
  sb.id,NULL,sb.status,'SYSTEM',NULL,'BACKFILL',sb.created_at
FROM scheduled_bookings sb
WHERE NOT EXISTS (
  SELECT 1
  FROM booking_status_history bsh
  WHERE bsh.booking_id=sb.id
);
