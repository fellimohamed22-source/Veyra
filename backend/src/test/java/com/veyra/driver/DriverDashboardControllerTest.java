package com.veyra.driver;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** DR-01: the « Disponible » switch and the home counters are scoped to the caller. */
@ExtendWith(MockitoExtension.class)
class DriverDashboardControllerTest {
  @Mock JdbcTemplate db;
  private final UUID userId = UUID.randomUUID();
  private final UUID driverId = UUID.randomUUID();

  @BeforeEach
  void setUp() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(userId, null));
    lenient().when(db.queryForList(eq("select id from drivers where user_id=?"), eq(UUID.class), eq(userId))).thenReturn(List.of(driverId));
  }

  @AfterEach
  void tearDown() { SecurityContextHolder.clearContext(); }

  @Test
  void availabilityIsStoredOnTheCallersOwnRow() {
    var controller = new DriverDashboardController(db);
    assertEquals(Map.of("acceptingRequests", false), controller.setAvailability(new DriverDashboardController.Availability(false)));
    verify(db).update("update drivers set accepting_requests=? where id=?", false, driverId);
    assertEquals("AVAILABILITY_REQUIRED",
        assertThrows(ApiException.class, () -> controller.setAvailability(new DriverDashboardController.Availability(null))).code());
  }

  @Test
  void dashboardCountsTheCallersRequestsOffersAndRides() {
    when(db.queryForObject(eq("select accepting_requests from drivers where id=?"), eq(Boolean.class), eq(driverId))).thenReturn(true);
    when(db.queryForObject(contains("from scheduled_bookings sb where sb.status in"), eq(Long.class), eq(driverId))).thenReturn(5L);
    when(db.queryForObject(contains("from driver_offers"), eq(Long.class), eq(driverId))).thenReturn(2L);
    when(db.queryForObject(contains("selected_driver_id=? and status in"), eq(Long.class), eq(driverId))).thenReturn(1L);
    when(db.queryForList(contains("order by sb.scheduled_at asc limit 1"), eq(driverId)))
        .thenReturn(List.of(Map.of("id", UUID.randomUUID(), "status", "CONFIRMED")));

    var dashboard = new DriverDashboardController(db).dashboard();

    assertEquals(true, dashboard.get("acceptingRequests"));
    assertEquals(5L, dashboard.get("availableRequests"));
    assertEquals(2L, dashboard.get("pendingOffers"));
    assertEquals(1L, dashboard.get("upcomingRides"));
    assertNotNull(dashboard.get("nextRide"));
  }

  @Test
  void aUserWithoutDriverProfileIsRefused() {
    when(db.queryForList(eq("select id from drivers where user_id=?"), eq(UUID.class), eq(userId))).thenReturn(List.of());
    assertEquals("DRIVER_PROFILE_REQUIRED", assertThrows(ApiException.class, () -> new DriverDashboardController(db).availability()).code());
  }
}
