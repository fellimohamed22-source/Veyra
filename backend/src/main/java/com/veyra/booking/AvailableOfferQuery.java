package com.veyra.booking;

public final class AvailableOfferQuery {
  private AvailableOfferQuery() {}
  // Correlated with the scheduled_bookings alias sb; matches selectable offers.
  private static final String SELECTABLE = "from driver_offers o join drivers od on od.id=o.driver_id " +
      "where o.booking_id=sb.id and o.status='ACTIVE' and o.expires_at>now() " +
      "and sb.status in ('OPEN_FOR_OFFERS','OFFERS_RECEIVED') and sb.offer_window_ends_at>now() " +
      "and od.status='ACTIVE' and od.kyc_status='APPROVED' and od.marketplace_enabled=true " +
      "and exists(select 1 from vehicles ov where ov.driver_id=od.id and ov.status='APPROVED' and ov.category_id=sb.category_id and " + com.veyra.company.FleetRules.usable("ov") + ")";
  public static final String COUNT_SQL = "(select count(*) " + SELECTABLE + ")";
  /** Lowest frozen customer total among the same selectable offers (board 05 "Meilleur prix disponible"). */
  public static final String BEST_TOTAL_SQL = "(select min(o.customer_total_minor) " + SELECTABLE + ")";
}
