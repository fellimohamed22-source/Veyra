package com.veyra.booking;

import com.veyra.booking.BookingDtos.*;
import com.veyra.finance.LedgerService;
import com.veyra.security.PinCrypto;
import com.veyra.shared.ApiException;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import java.time.OffsetDateTime;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class BookingCreationReplayTest {
  JdbcTemplate db=mock(JdbcTemplate.class);
  UUID user=UUID.randomUUID(),booking=UUID.randomUUID();
  BookingController controller=new BookingController(db,mock(PasswordEncoder.class),mock(PinCrypto.class),mock(LedgerService.class),120,24,60,30,mock(BookingStatusHistoryService.class));
  Create request=new Create(new Point(43,6,"Départ"),new Point(44,7,"Destination"),OffsetDateTime.now().plusHours(5),UUID.randomUUID(),"CASH","CLIENT",null,null,null,1,0,null,null);
  @BeforeEach void setup(){SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(user,null));}
  @AfterEach void cleanup(){SecurityContextHolder.clearContext();}
  @Test void replayReturnsExistingBookingWithoutAnotherPublication(){
    when(db.queryForList(contains("from booking_creation_requests"),eq(user),eq("request-1"))).thenReturn(List.of(Map.of("request_body",request.toString(),"booking_id",booking)));
    assertEquals(booking,controller.createIdempotently(request,"request-1").getBody().get("id"));
    verify(db,never()).update(anyString(),any(Object[].class));
    verify(db).queryForList(contains("pg_advisory_xact_lock"),eq(user+":request-1"));
  }
  @Test void sameKeyCannotBeReusedWithDifferentTrip(){
    when(db.queryForList(contains("from booking_creation_requests"),eq(user),eq("request-1"))).thenReturn(List.of(Map.of("request_body","another trip","booking_id",booking)));
    assertEquals("IDEMPOTENCY_KEY_CONFLICT",assertThrows(ApiException.class,()->controller.createIdempotently(request,"request-1")).code());
  }
  @Test void rejectsPassengersExceedingCategoryCapacityBeforePublication(){
    when(db.queryForList(contains("select capacity"),eq(request.categoryId()))).thenReturn(List.of(Map.<String,Object>of("capacity",0)));
    assertEquals("CATEGORY_CAPACITY_EXCEEDED",assertThrows(ApiException.class,()->controller.create(request)).code());
    verify(db,never()).update(anyString(),any(Object[].class));
  }
  @Test void rejectsBaggageExceedingAConfiguredCategoryCapacity(){
    Create withBags=new Create(request.pickup(),request.dropoff(),request.scheduledAt(),request.categoryId(),"CASH","CLIENT",null,null,null,1,4,null,null);
    when(db.queryForList(contains("select capacity"),eq(request.categoryId()))).thenReturn(List.of(Map.<String,Object>of("capacity",4,"baggage_capacity",3)));
    assertEquals("CATEGORY_BAGGAGE_CAPACITY_EXCEEDED",assertThrows(ApiException.class,()->controller.create(withBags)).code());
    verify(db,never()).update(anyString(),any(Object[].class));
  }
  @Test void unconfiguredBaggageCapacityIsNotEnforced(){
    // NULL baggage_capacity: the admin has not validated capacities yet,
    // so the booking proceeds past the capacity checks (and fails later
    // on the unstubbed visibility policy, which proves it got there).
    Create withBags=new Create(request.pickup(),request.dropoff(),request.scheduledAt(),request.categoryId(),"CASH","CLIENT",null,null,null,1,12,null,null);
    Map<String,Object> row=new HashMap<>();row.put("capacity",4);row.put("baggage_capacity",null);
    when(db.queryForList(contains("select capacity"),eq(request.categoryId()))).thenReturn(List.of(row));
    assertDoesNotThrow(()->{try{controller.create(withBags);}catch(ApiException e){if(e.code().startsWith("CATEGORY_"))throw e;}});
  }
  @Test void unavailableCategoryIsAValidationError(){
    assertEquals("CATEGORY_UNAVAILABLE",assertThrows(ApiException.class,()->controller.create(request)).code());
    verify(db,never()).update(anyString(),any(Object[].class));
  }
  @Test void entryPointsOwnTransactionsAndPinFailuresPersist()throws Exception{
    for(String method:List.of("enroute","arrived"))assertNotNull(BookingController.class.getDeclaredMethod(method,UUID.class).getAnnotation(Transactional.class));
    var annotation=BookingController.class.getDeclaredMethod("start",UUID.class,BookingController.Pin.class).getAnnotation(Transactional.class);
    assertTrue(Arrays.asList(annotation.noRollbackFor()).contains(ApiException.class));
  }
}
