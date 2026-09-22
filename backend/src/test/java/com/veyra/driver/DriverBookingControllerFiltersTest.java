package com.veyra.driver;

import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import java.util.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class DriverBookingControllerFiltersTest {
  JdbcTemplate db=mock(JdbcTemplate.class);
  UUID user=UUID.randomUUID(),driver=UUID.randomUUID();
  @BeforeEach void setup(){
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(user,null));
    when(db.queryForList(anyString(),eq(UUID.class),eq(user))).thenReturn(List.of(driver));
  }
  @AfterEach void cleanup(){SecurityContextHolder.clearContext();}
  @Test void allScopeIncludesHistoryAndFiltersBeforePagination(){
    new DriverBookingController(db).mine("all","COMPLETED","desc",2);
    verify(db).queryForList(argThat(sql->sql.contains("'COMPLETED'")&&sql.contains("'CUSTOMER_NO_SHOW'")&&sql.contains("and sb.status=?")&&sql.contains("order by sb.scheduled_at desc,sb.id limit 10 offset 20")),eq(driver),eq("COMPLETED"));
  }
  @Test void arrivedIsExactAndNegativePageCannotProduceNegativeOffset(){
    new DriverBookingController(db).mine("all","DRIVER_ARRIVED","asc",-2);
    verify(db).queryForList(argThat(sql->sql.contains("and sb.status=?")&&sql.endsWith("limit 10 offset 0")),eq(driver),eq("DRIVER_ARRIVED"));
  }
}
