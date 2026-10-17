package com.veyra.guest;

import com.veyra.provider.SmsProvider;
import com.veyra.shared.ApiException;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.sql.Timestamp;
import java.time.OffsetDateTime;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class GuestLinkControllerTest {
  JdbcTemplate db=mock(JdbcTemplate.class);
  SmsProvider sms=mock(SmsProvider.class);
  GuestLinkController controller=new GuestLinkController(db,sms,"https://veyra.example");
  UUID user=UUID.randomUUID(),partner=UUID.randomUUID(),booking=UUID.randomUUID();

  @BeforeEach void auth(){SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(user,null));}
  @AfterEach void clear(){SecurityContextHolder.clearContext();}

  void memberWithBooking(String status,String phone){
    when(db.queryForObject(contains("from partner_users"),eq(Integer.class),eq(partner),eq(user))).thenReturn(1);
    Map<String,Object> b=new HashMap<>();
    b.put("status",status);
    b.put("scheduled_at",Timestamp.from(OffsetDateTime.now().plusDays(1).toInstant()));
    b.put("beneficiary_phone_snapshot",phone);
    when(db.queryForList(contains("from scheduled_bookings where id=? and partner_id=?"),eq(booking),eq(partner))).thenReturn(List.of(b));
  }

  @Test void createsAnUnguessableLinkStoringOnlyItsHashAndReplacingThePreviousOne(){
    memberWithBooking("OPEN_FOR_OFFERS","06 12 34 56 78");
    var result=controller.create(partner,booking,null);
    String url=(String)result.get("url");
    assertTrue(url.startsWith("https://veyra.example/suivi/"));
    String token=url.substring(url.lastIndexOf('/')+1);
    assertTrue(GuestLinkController.TOKEN.matcher(token).matches());
    verify(db).update(contains("set revoked_at=now() where booking_id=?"),eq(booking));
    verify(db).update(contains("insert into guest_access_links"),eq(booking),eq(GuestLinkController.sha256(token)),any(),eq(user));
    verifyNoInteractions(sms);
  }

  @Test void smsGoesToTheBeneficiaryInInternationalFormat(){
    memberWithBooking("CONFIRMED","06 12 34 56 78");
    when(sms.isConfigured()).thenReturn(true);
    when(sms.send(anyString(),anyString())).thenReturn(true);
    var result=controller.create(partner,booking,new GuestLinkController.LinkRequest(true));
    assertEquals(true,result.get("smsSent"));
    verify(sms).send(eq("+33612345678"),contains("/suivi/"));
  }

  @Test void smsIsRefusedWhenTwilioIsNotConfigured(){
    memberWithBooking("CONFIRMED","+33612345678");
    when(sms.isConfigured()).thenReturn(false);
    assertEquals("SMS_NOT_CONFIGURED",assertThrows(ApiException.class,()->controller.create(partner,booking,new GuestLinkController.LinkRequest(true))).code());
  }

  @Test void anotherOrganisationCannotCreateALink(){
    when(db.queryForObject(contains("from partner_users"),eq(Integer.class),eq(partner),eq(user))).thenReturn(0);
    assertEquals("PARTNER_SCOPE_FORBIDDEN",assertThrows(ApiException.class,()->controller.create(partner,booking,null)).code());
  }

  @Test void part03_unknownExpiredOrMalformedLinksAllAnswerTheSame404(){
    assertEquals("GUEST_LINK_INVALID",assertThrows(ApiException.class,()->controller.view("../../etc")).code());
    String wellFormed="A".repeat(43);
    when(db.queryForList(contains("from guest_access_links"),eq(GuestLinkController.sha256(wellFormed)))).thenReturn(List.of());
    assertEquals("GUEST_LINK_INVALID",assertThrows(ApiException.class,()->controller.view(wellFormed)).code());
  }

  @Test void publicViewNeverExposesPhoneNumbersOrPricesAndHidesTheDriverBeforeConfirmation(){
    String token="B".repeat(43);
    Map<String,Object> row=new HashMap<>();
    row.put("id",booking);row.put("status","OFFERS_RECEIVED");row.put("scheduled_at",Timestamp.from(OffsetDateTime.now().toInstant()));
    row.put("pickup_address","Hôtel Le Marceau");row.put("dropoff_address","Orly");row.put("beneficiary_name_snapshot","Jean Dubois");
    row.put("driver_first_name",null);
    when(db.queryForList(contains("from guest_access_links"),eq(GuestLinkController.sha256(token)))).thenReturn(List.of(row));
    var response=controller.view(token);
    var body=response.getBody();
    assertEquals("Jean",body.get("passengerFirstName"));
    assertFalse(body.containsKey("driverFirstName"));
    assertTrue(body.keySet().stream().noneMatch(k->k.toLowerCase().contains("phone")||k.toLowerCase().contains("price")||k.toLowerCase().contains("minor")));
    assertEquals("noindex, nofollow",response.getHeaders().getFirst("X-Robots-Tag"));
  }

  @Test void phoneNormalisation(){
    assertEquals("+33612345678",GuestLinkController.toE164("06.12.34.56.78"));
    assertEquals("+447911123456",GuestLinkController.toE164("+44 7911 123456"));
    assertNull(GuestLinkController.toE164("12"));
  }
}
