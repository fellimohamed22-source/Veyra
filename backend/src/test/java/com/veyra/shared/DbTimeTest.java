package com.veyra.shared;

import org.junit.jupiter.api.Test;

import java.sql.Timestamp;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Real conversion logic that fixes a confirmed production bug
 * (ClassCastException: java.sql.Timestamp cannot be cast to
 * java.time.OffsetDateTime) -- PostgreSQL's JDBC driver doesn't
 * consistently return OffsetDateTime for TIMESTAMPTZ columns read via
 * JdbcTemplate's generic queryForList/queryForMap.
 */
class DbTimeTest {

  @Test
  void nullPassesThroughAsNull() {
    assertNull(DbTime.toOffsetDateTime(null));
  }

  @Test
  void anAlreadyCorrectOffsetDateTimeIsReturnedUnchanged() {
    OffsetDateTime odt = OffsetDateTime.now();

    assertSame(odt, DbTime.toOffsetDateTime(odt));
  }

  @Test
  void aSqlTimestampIsConvertedAsUtc() {
    // The exact real-world shape that was crashing: a plain
    // java.sql.Timestamp instead of the expected OffsetDateTime.
    Instant instant = Instant.parse("2026-09-12T15:22:00Z");
    Timestamp ts = Timestamp.from(instant);

    OffsetDateTime result = DbTime.toOffsetDateTime(ts);

    assertEquals(instant.atOffset(ZoneOffset.UTC), result);
  }

  @Test
  void anUnexpectedTypeFailsClearlyRatherThanSilently() {
    assertThrows(IllegalStateException.class, () -> DbTime.toOffsetDateTime("not a timestamp"));
  }
}
