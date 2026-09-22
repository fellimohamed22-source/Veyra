package com.veyra.booking;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class CustomerFavoritesControllerTest {
  JdbcTemplate db=mock(JdbcTemplate.class);
  UUID user=UUID.randomUUID(),booking=UUID.randomUUID(),driver=UUID.randomUUID();
  @BeforeEach void setup(){SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(user,null));}
  @AfterEach void cleanup(){SecurityContextHolder.clearContext();}
  @Test void favoriteRequiresAnOwnedCompletedBooking(){
    when(db.queryForList(anyString(),eq(UUID.class),eq(booking),eq(user))).thenReturn(List.of());
    assertEquals("COMPLETED_BOOKING_REQUIRED",assertThrows(ApiException.class,()->new CustomerFavoritesController(db).addDriver(booking)).code());
    verify(db,never()).update(anyString(),any(Object[].class));
  }
  @Test void replayAddingFavoriteUsesAnUpsert(){
    when(db.queryForList(anyString(),eq(UUID.class),eq(booking),eq(user))).thenReturn(List.of(driver));
    new CustomerFavoritesController(db).addDriver(booking);
    verify(db).update(contains("on conflict(user_id,driver_id)"),eq(user),eq(driver),eq(booking));
  }
  @Test void savedAddressDeletionIsScopedToOwner(){
    UUID address=UUID.randomUUID();
    assertThrows(ApiException.class,()->new CustomerFavoritesController(db).deleteAddress(address));
    verify(db).update(contains("where id=? and user_id=?"),eq(address),eq(user));
  }
}
