package com.veyra.auth;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class ConsentServiceTest {
  JdbcTemplate db=mock(JdbcTemplate.class);
  ConsentService service=new ConsentService(db,"terms-v1","privacy-v1","marketing-v1");

  @Test
  void signupRecordsThreeDistinctDecisionsWithTheirDocumentVersions(){
    UUID user=UUID.randomUUID();
    service.recordSignup(user,false,"SIGNUP_CLIENT");
    verify(db).update(contains("insert into user_consents"),eq(user),eq("TERMS"),eq(true),eq("terms-v1"),eq("SIGNUP_CLIENT"));
    verify(db).update(contains("insert into user_consents"),eq(user),eq("PRIVACY"),eq(true),eq("privacy-v1"),eq("SIGNUP_CLIENT"));
    verify(db).update(contains("insert into user_consents"),eq(user),eq("MARKETING"),eq(false),eq("marketing-v1"),eq("SIGNUP_CLIENT"));
  }

  @Test
  void unknownConsentTypeIsRejected(){
    assertEquals("INVALID_CONSENT_TYPE",assertThrows(ApiException.class,()->service.record(UUID.randomUUID(),"PROFILING",true,"X")).code());
  }

  @Test
  void mandatoryConsentsMustBeExplicitlyTrue(){
    assertThrows(ApiException.class,()->ConsentService.requireMandatory(null,null));
    assertDoesNotThrow(()->ConsentService.requireMandatory(true,true));
  }
}
