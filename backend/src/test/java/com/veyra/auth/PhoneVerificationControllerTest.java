package com.veyra.auth;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class PhoneVerificationControllerTest {
  JdbcTemplate db=mock(JdbcTemplate.class);
  UUID user=UUID.randomUUID();
  Map<String,Object> claims=new HashMap<>();
  PhoneVerificationController controller=new PhoneVerificationController(db,"veyra-4806a"){
    @Override Map<String,Object> verifyToken(String idToken){return claims;}
  };

  @BeforeEach void auth(){SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(user,null));}
  @AfterEach void clear(){SecurityContextHolder.clearContext();}

  @Test void smsSignInMarksThePhoneVerified(){
    claims.put("provider","phone");
    claims.put("phone_number","+33612345678");
    when(db.queryForObject(contains("phone_verified_at is not null"),eq(Integer.class),eq("+33612345678"),eq(user),eq(user))).thenReturn(0);
    assertEquals(true,controller.verify(new PhoneVerificationController.Proof("t")).get("verified"));
    verify(db).update(contains("phone_verified_at=now()"),eq("+33612345678"),eq(user));
  }

  @Test void tokenFromAnotherProviderDoesNotProveThePhone(){
    claims.put("provider","google.com");
    claims.put("phone_number","+33612345678");
    assertEquals("PHONE_PROOF_REQUIRED",assertThrows(ApiException.class,()->controller.verify(new PhoneVerificationController.Proof("t"))).code());
    verify(db,never()).update(anyString(),any(Object[].class));
  }

  @Test void aPhoneVerifiedByAnotherAccountIsRefused(){
    claims.put("provider","phone");
    claims.put("phone_number","+33612345678");
    when(db.queryForObject(contains("phone_verified_at is not null"),eq(Integer.class),eq("+33612345678"),eq(user),eq(user))).thenReturn(1);
    assertEquals("PHONE_ALREADY_USED",assertThrows(ApiException.class,()->controller.verify(new PhoneVerificationController.Proof("t"))).code());
  }
}
