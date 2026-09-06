package com.veyra.shared;

import java.sql.Timestamp;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

/**
 * Real, confirmed production bug this exists to fix:
 * java.lang.ClassCastException: class java.sql.Timestamp cannot be cast
 * to class java.time.OffsetDateTime -- found from an actual stack trace
 * (Render logs), not by static review. Reading a TIMESTAMPTZ column
 * through JdbcTemplate's generic queryForList/queryForMap (which uses
 * ResultSet.getObject(columnIndex) under the hood via
 * ColumnMapRowMapper) does not consistently return OffsetDateTime --
 * the PostgreSQL JDBC driver can return java.sql.Timestamp instead,
 * depending on the exact query/column path, and every direct
 * (OffsetDateTime) cast on such a value was a latent crash waiting for
 * whichever code path happened to hit the Timestamp-returning case
 * first (which is exactly what happened here, invisible to every unit
 * test that mocks JdbcTemplate directly with a real OffsetDateTime
 * already in hand).
 *
 * Storage is UTC throughout this project
 * (properties.hibernate.jdbc.time_zone: UTC already configured), so a
 * bare Timestamp is safely reinterpreted as a UTC instant here rather
 * than guessing at a different offset.
 */
public final class DbTime {
  private DbTime() {}

  public static OffsetDateTime toOffsetDateTime(Object value) {
    if (value == null) return null;
    if (value instanceof OffsetDateTime odt) return odt;
    if (value instanceof Timestamp ts) return ts.toInstant().atOffset(ZoneOffset.UTC);
    throw new IllegalStateException("Cannot convert to OffsetDateTime: " + value.getClass());
  }
}
