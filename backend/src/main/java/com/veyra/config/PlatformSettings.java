package com.veyra.config;

import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;

/**
 * Business parameters stored in platform_settings (V042), editable by an
 * admin without redeploying. Every read falls back to the caller's
 * default (application.yml value) when the row is absent, so behaviour is
 * unchanged on a database that has not run V042 yet.
 *
 * Plain JDBC on purpose, built from the caller's JdbcTemplate.
 */
public class PlatformSettings {
  public static final String MIN_LEAD_MINUTES="booking.min_lead_minutes";
  public static final String MAX_OFFER_WINDOW_HOURS="booking.max_offer_window_hours";
  public static final String NORMAL_CLOSE_BEFORE_MINUTES="booking.normal_close_before_minutes";
  public static final String SHORT_CLOSE_BEFORE_MINUTES="booking.short_close_before_minutes";
  public static final String PICKUP_RADIUS_METERS="ride.pickup_radius_meters";
  public static final String LOCATION_MAX_AGE_SECONDS="ride.location_max_age_seconds";

  private final JdbcTemplate db;

  public PlatformSettings(JdbcTemplate db){
    this.db=db;
  }

  public long get(String key,long fallback){
    List<Long> rows=db.queryForList("select value_number from platform_settings where setting_key=?",Long.class,key);
    return rows==null||rows.isEmpty()||rows.getFirst()==null?fallback:rows.getFirst();
  }
}
