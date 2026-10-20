package com.veyra.company;

/**
 * Marketplace rules for fleet vehicles (SOC-01, SOC-09): a company vehicle
 * can carry offers only while its company is approved by VEYRA and none
 * of its current documents has expired. A driver's own vehicle
 * (company_id null) is unaffected.
 */
public final class FleetRules {
  private FleetRules() {}

  /** SQL condition on the vehicles alias {@code v}. */
  public static String usable(String v) {
    return "((" + v + ".company_id is null or exists(select 1 from vtc_companies fc where fc.id=" + v + ".company_id and fc.status='APPROVED'))" +
        " and not exists(select 1 from company_documents fd where fd.vehicle_id=" + v + ".id and fd.status<>'SUPERSEDED' and fd.expires_at<current_date))";
  }

  /**
   * Owner decision 20/10/2026, every driver type: the VTC card must still be
   * valid on the ride day (Paris date), checked before each offer. Parameters:
   * booking id, driver id, driver id. Valid through its expiry date.
   */
  public static final String VTC_CARD_EXPIRES_BEFORE_RIDE_SQL =
      "select count(*) from scheduled_bookings sb where sb.id=? and (" +
      "exists(select 1 from driver_vtc_registrations r where r.driver_id=? and r.expires_at<(sb.scheduled_at at time zone 'Europe/Paris')::date)" +
      " or exists(select 1 from driver_documents dd where dd.driver_id=? and dd.type='VTC_CARD' and dd.status in ('SUBMITTED','APPROVED')" +
      " and dd.expires_at<(sb.scheduled_at at time zone 'Europe/Paris')::date))";

  /** Current driver documents past their expiry date block new offers. */
  public static final String DRIVER_DOCUMENT_EXPIRED_SQL =
      "select count(*) from driver_documents where driver_id=? and status in ('SUBMITTED','APPROVED') and expires_at<current_date";
}
