package com.veyra.driver;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.*;

/**
 * Gap P0 from the UI kit (GAPS_REQUIRED_CHANGES.md #2 / screen D18):
 * "Mes offres" had no dedicated endpoint -- the mobile driver app could
 * only reconstruct a partial view via /driver/opportunities and booking
 * detail calls, never a real per-driver offer history. driver_offers
 * already had everything needed (status, proposed_amount_minor,
 * expires_at, booking_id); this just exposes it directly, scoped to the
 * calling driver only.
 */
@RestController
@RequestMapping("/api/v1/driver/offers")
public class DriverOffersController {
  private final JdbcTemplate db;

  public DriverOffersController(JdbcTemplate db){
    this.db=db;
  }

  private static final Set<String> VALID_SCOPES=Set.of("active","won","closed");

  @GetMapping
  public List<Map<String,Object>> list(@RequestParam(defaultValue="active") String scope){
    if(!VALID_SCOPES.contains(scope)){
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"INVALID_OFFER_SCOPE");
    }
    UUID driverId=driverId();
    String statusFilter=switch(scope){
      case "won" -> "o.status='ACCEPTED'";
      case "closed" -> "o.status in ('REJECTED_BY_SELECTION','EXPIRED','WITHDRAWN','SUPERSEDED')";
      default -> "o.status='ACTIVE'";
    };
    // Raw snake_case column labels, same convention as
    // DriverOpportunityController and BookingController's driver-facing
    // endpoints -- not remapped to camelCase here.
    return db.queryForList(
        "select o.id as offer_id,o.booking_id,o.proposed_amount_minor,o.currency,o.status,o.expires_at,o.created_at," +
        "sb.pickup_address,sb.dropoff_address,sb.scheduled_at,sb.status as booking_status " +
        "from driver_offers o join scheduled_bookings sb on sb.id=o.booking_id " +
        "where o.driver_id=? and "+statusFilter+" " +
        "order by o.created_at desc",
        driverId);
  }

  private UUID driverId(){
    List<UUID> rows=db.queryForList(
        "select id from drivers where user_id=?",
        UUID.class,CurrentUser.id());
    if(rows.isEmpty()) throw new ApiException(HttpStatus.FORBIDDEN,"DRIVER_PROFILE_REQUIRED");
    return rows.getFirst();
  }
}
