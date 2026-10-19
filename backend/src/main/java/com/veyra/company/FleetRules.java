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

  /** Current driver documents past their expiry date block new offers. */
  public static final String DRIVER_DOCUMENT_EXPIRED_SQL =
      "select count(*) from driver_documents where driver_id=? and status in ('SUBMITTED','APPROVED') and expires_at<current_date";
}
