package com.veyra.booking;

import com.veyra.finance.LedgerService;
import com.veyra.security.PinCrypto;
import com.veyra.shared.ApiException;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
import java.sql.ResultSet;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class OwnerOfferSummaryTest {
  JdbcTemplate db=mock(JdbcTemplate.class);
  UUID user=UUID.randomUUID(),booking=UUID.randomUUID();
  BookingController controller=new BookingController(db,mock(PasswordEncoder.class),mock(PinCrypto.class),mock(LedgerService.class),120,24,60,30,mock(BookingStatusHistoryService.class));
  @BeforeEach void setup(){SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(user,null));}
  @AfterEach void cleanup(){SecurityContextHolder.clearContext();}

  @Test void rejectsAnotherCustomersOfferList(){
    when(db.queryForList(anyString(),eq(booking))).thenReturn(List.of(Map.of("creator_user_id",UUID.randomUUID())));
    assertEquals("FORBIDDEN",assertThrows(ApiException.class,()->controller.ownerOffers(booking)).code());
  }

  @Test void summaryKeepsCustomerTotalAndApprovedVehicleDetails() throws Exception {
    when(db.queryForList(anyString(),eq(booking))).thenReturn(List.of(Map.of("creator_user_id",user)));
    when(db.queryForObject(contains("commission_bps"),eq(Integer.class))).thenReturn(1500);
    ResultSet row=mock(ResultSet.class);
    when(row.getLong("proposed_amount_minor")).thenReturn(10000L);
    when(row.getString("currency")).thenReturn("EUR");
    when(row.getString("brand")).thenReturn("Mercedes");
    when(row.getString("vehicle_category")).thenReturn("Berline");
    when(db.query(anyString(),org.mockito.ArgumentMatchers.<RowMapper<Map<String,Object>>>any(),eq(booking))).thenAnswer(invocation->{
      RowMapper<Map<String,Object>> mapper=invocation.getArgument(1);
      return List.of(mapper.mapRow(row,0));
    });
    Map<String,Object> result=controller.ownerOffers(booking).getFirst();
    assertEquals(10000L,result.get("driverPriceMinor"));
    assertEquals(1500L,result.get("commissionMinor"));
    assertEquals(11500L,result.get("totalMinor"));
    assertEquals("Mercedes",result.get("vehicleBrand"));
    assertEquals("Berline",result.get("vehicleCategory"));
    assertEquals(true,result.get("driverVerified"));
  }
}
