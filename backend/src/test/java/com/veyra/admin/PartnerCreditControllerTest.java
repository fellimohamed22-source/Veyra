package com.veyra.admin;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Real validation boundaries (negative credit limit, payment terms
 * outside 1-90 days) had zero coverage before this -- an admin fat-
 * fingering a negative limit or a 0/365-day term is exactly the kind of
 * input this check exists to catch before it reaches partner_organizations.
 */
@ExtendWith(MockitoExtension.class)
class PartnerCreditControllerTest {

  @Mock JdbcTemplate db;

  private PartnerCreditController controller() {
    return new PartnerCreditController(db);
  }

  @Test
  void negativeCreditLimitRejectedWithoutWritingAnything() {
    UUID partnerId = UUID.randomUUID();

    assertThrows(IllegalArgumentException.class,
        () -> controller().credit(partnerId, new PartnerCreditController.Credit(-100, 30, "MONTHLY")));

    verifyNoInteractions(db);
  }

  @Test
  void paymentTermsBelowOneDayRejected() {
    UUID partnerId = UUID.randomUUID();

    assertThrows(IllegalArgumentException.class,
        () -> controller().credit(partnerId, new PartnerCreditController.Credit(500000, 0, "MONTHLY")));

    verifyNoInteractions(db);
  }

  @Test
  void paymentTermsAboveNinetyDaysRejected() {
    UUID partnerId = UUID.randomUUID();

    assertThrows(IllegalArgumentException.class,
        () -> controller().credit(partnerId, new PartnerCreditController.Credit(500000, 91, "MONTHLY")));

    verifyNoInteractions(db);
  }

  @Test
  void boundaryValuesAreAccepted() {
    // 1 and 90 are the real inclusive boundaries (paymentTermsDays()<1 ||
    // paymentTermsDays()>90) -- both must be accepted, not just values
    // strictly inside the range.
    UUID partnerId = UUID.randomUUID();

    assertDoesNotThrow(() -> controller().credit(partnerId, new PartnerCreditController.Credit(0, 1, "MONTHLY")));
    assertDoesNotThrow(() -> controller().credit(partnerId, new PartnerCreditController.Credit(0, 90, "MONTHLY")));
  }

  @Test
  void validCreditApprovesTheLimitAndUpsertsTheInvoiceAccount() {
    UUID partnerId = UUID.randomUUID();

    controller().credit(partnerId, new PartnerCreditController.Credit(500000, 45, "MONTHLY"));

    verify(db).update(contains("credit_status='APPROVED'"), eq(500000L), eq(partnerId));
    verify(db).update(contains("on conflict(partner_id) do update"), eq(partnerId), eq(45), eq("MONTHLY"));
  }
}
