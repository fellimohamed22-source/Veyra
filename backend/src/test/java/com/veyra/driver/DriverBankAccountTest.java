package com.veyra.driver;

import com.veyra.security.PinCrypto;
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

/** Payout bank account: IBAN checked (mod 97), stored encrypted, shown masked. */
@ExtendWith(MockitoExtension.class)
class DriverBankAccountTest {
  @Mock JdbcTemplate db;
  final UUID user = UUID.randomUUID(), driver = UUID.randomUUID();
  final PinCrypto crypto = new PinCrypto("test-only-key-of-32-bytes-long!!");

  @BeforeEach void auth() { SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(user, null)); }
  @AfterEach void clear() { SecurityContextHolder.clearContext(); }

  DriverOnboardingController controller() { return new DriverOnboardingController(db, crypto); }

  @Test void ibanChecksum() {
    assertTrue(DriverOnboardingController.validIban(DriverOnboardingController.normalizeIban("FR76 3000 6000 0112 3456 7890 189")));
    assertTrue(DriverOnboardingController.validIban("DE89370400440532013000"));
    assertFalse(DriverOnboardingController.validIban("FR7630006000011234567890188"), "wrong check digits");
    assertFalse(DriverOnboardingController.validIban("FR76300060000112345678901"), "French IBAN is 27 characters");
  }

  @Test void invalidIbanIsRefused() {
    var e = assertThrows(ApiException.class, () -> controller().bank(new DriverOnboardingController.Bank("Karim Benali", "FR00 1234", null)));
    assertEquals("IBAN_INVALID", e.code());
    verify(db, never()).update(anyString(), any(Object[].class));
  }

  @Test void validIbanIsStoredEncryptedWithLastDigits() {
    when(db.queryForObject(contains("from drivers where user_id=?"), eq(UUID.class), eq(user))).thenReturn(driver);
    var r = controller().bank(new DriverOnboardingController.Bank(" Karim Benali ", "fr76 3000 6000 0112 3456 7890 189", "bnpafrpp"));
    assertTrue(r.get("ibanMasked").toString().endsWith("0189"));
    verify(db).update(contains("insert into driver_bank_accounts"), eq(driver), eq("Karim Benali"),
        argThat((String enc) -> !enc.contains("3000") && crypto.decrypt(enc).equals("FR7630006000011234567890189")),
        eq("FR"), eq("0189"), eq("BNPAFRPP"));
  }
}
