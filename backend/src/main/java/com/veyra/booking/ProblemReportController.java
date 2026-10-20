package com.veyra.booking;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.*;

/**
 * « Signaler un problème » (board 10 P4): the client who booked, a member of
 * the booking establishment, or the selected driver reports an issue on a
 * ride; support lists and resolves reports.
 */
@RestController
public class ProblemReportController {
  static final Set<String> CATEGORIES = Set.of("DRIVER_LATE", "DRIVER_NOT_FOUND", "SAFETY", "VEHICLE", "ROUTE", "PAYMENT", "OTHER");

  private final JdbcTemplate db;

  public ProblemReportController(JdbcTemplate db) { this.db = db; }

  public record Report(String category, String message) {}

  @PostMapping("/api/v1/bookings/{id}/problem-reports")
  public ResponseEntity<Map<String, Object>> report(@PathVariable UUID id, @RequestBody Report r) {
    String category = r == null || r.category() == null ? "" : r.category().trim().toUpperCase(Locale.ROOT);
    if (!CATEGORIES.contains(category)) throw new ApiException(HttpStatus.BAD_REQUEST, "PROBLEM_CATEGORY_INVALID");
    String message = r.message() == null ? null : r.message().trim();
    if (message != null && message.length() > 1000) throw new ApiException(HttpStatus.BAD_REQUEST, "PROBLEM_MESSAGE_TOO_LONG");
    Integer allowed = db.queryForObject(
        "select count(*) from scheduled_bookings sb where sb.id=? and (sb.creator_user_id=? " +
        "or exists(select 1 from drivers d where d.id=sb.selected_driver_id and d.user_id=?) " +
        "or exists(select 1 from partner_users pu where pu.partner_id=sb.partner_id and pu.user_id=? and pu.status='ACTIVE'))",
        Integer.class, id, CurrentUser.id(), CurrentUser.id(), CurrentUser.id());
    if (allowed == null || allowed == 0) throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN");
    UUID reportId = UUID.randomUUID();
    db.update("insert into problem_reports(id,booking_id,reporter_user_id,category,message) values (?,?,?,?,?)",
        reportId, id, CurrentUser.id(), category, message == null || message.isEmpty() ? null : message);
    return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("id", reportId, "status", "OPEN"));
  }

  @GetMapping("/api/v1/support/problem-reports")
  @PreAuthorize("hasAnyRole('SUPPORT','ADMIN')")
  public List<Map<String, Object>> open() {
    return db.queryForList(
        "select pr.id,pr.booking_id,pr.category,pr.message,pr.status,pr.created_at,u.first_name,u.last_name,u.email::text as email,sb.status as booking_status,sb.scheduled_at " +
        "from problem_reports pr join users u on u.id=pr.reporter_user_id join scheduled_bookings sb on sb.id=pr.booking_id " +
        "where pr.status='OPEN' order by pr.created_at desc limit 200");
  }

  @PostMapping("/api/v1/support/problem-reports/{reportId}/resolve")
  @PreAuthorize("hasAnyRole('SUPPORT','ADMIN')")
  public Map<String, Object> resolve(@PathVariable UUID reportId) {
    int n = db.update("update problem_reports set status='RESOLVED',resolved_at=now(),resolved_by=? where id=? and status='OPEN'", CurrentUser.id(), reportId);
    if (n == 0) throw new ApiException(HttpStatus.NOT_FOUND, "PROBLEM_REPORT_NOT_FOUND");
    return Map.of("status", "RESOLVED");
  }
}
