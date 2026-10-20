package com.veyra.booking;

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

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** « Signaler un problème »: only ride participants, known categories. */
@ExtendWith(MockitoExtension.class)
class ProblemReportControllerTest {
  @Mock JdbcTemplate db;
  final UUID user = UUID.randomUUID(), booking = UUID.randomUUID();

  @BeforeEach void auth() { SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(user, null)); }
  @AfterEach void clear() { SecurityContextHolder.clearContext(); }

  ProblemReportController controller() { return new ProblemReportController(db); }

  @Test void unknownCategoryIsRefused() {
    assertEquals("PROBLEM_CATEGORY_INVALID", assertThrows(ApiException.class,
        () -> controller().report(booking, new ProblemReportController.Report("ANGRY", null))).code());
    verifyNoInteractions(db);
  }

  @Test void someoneOutsideTheRideCannotReport() {
    when(db.queryForObject(contains("from scheduled_bookings sb where sb.id=?"), eq(Integer.class), eq(booking), eq(user), eq(user), eq(user))).thenReturn(0);
    assertEquals("FORBIDDEN", assertThrows(ApiException.class,
        () -> controller().report(booking, new ProblemReportController.Report("SAFETY", "x"))).code());
    verify(db, never()).update(anyString(), any(Object[].class));
  }

  @Test void participantReportIsStoredOpen() {
    when(db.queryForObject(contains("from scheduled_bookings sb where sb.id=?"), eq(Integer.class), eq(booking), eq(user), eq(user), eq(user))).thenReturn(1);
    var r = controller().report(booking, new ProblemReportController.Report("driver_late", "  Toujours pas là  "));
    assertEquals(201, r.getStatusCode().value());
    verify(db).update(contains("insert into problem_reports"), any(), eq(booking), eq(user), eq("DRIVER_LATE"), eq("Toujours pas là"));
  }
}
