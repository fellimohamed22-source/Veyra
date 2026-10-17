package com.veyra.commission;

import com.veyra.commission.CommissionEngine.*;
import com.veyra.shared.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class CommissionEngineTest {
  JdbcTemplate db=mock(JdbcTemplate.class);
  CommissionEngine engine=new CommissionEngine(db);

  static Rule rule(int bps,long fixed,Long min,Long max){
    return new Rule(UUID.randomUUID(),"STANDARD",bps,fixed,min,max);
  }

  @Test void methodA_tenPercentOnTheDriverPrice(){
    // Spec example: driver 100 EUR, 10 % -> commission 10 EUR, client 110 EUR.
    assertEquals(1000,CommissionEngine.commission(10000,rule(1000,0,null,null)));
  }

  @Test void zeroRateIsAllowed(){
    assertEquals(0,CommissionEngine.commission(10000,rule(0,0,null,null)));
  }

  @Test void roundingIsHalfUpToTheMinorUnit(){
    // 4 815 x 8 % = 385.2 -> 385 ; 4 825 x 10 % = 482.5 -> 483
    assertEquals(385,CommissionEngine.commission(4815,rule(800,0,null,null)));
    assertEquals(483,CommissionEngine.commission(4825,rule(1000,0,null,null)));
  }

  @Test void fixedAmountIsAddedToThePercentage(){
    assertEquals(1150,CommissionEngine.commission(10000,rule(1000,150,null,null)));
  }

  @Test void floorAndCeilingClampTheCommission(){
    assertEquals(500,CommissionEngine.commission(2000,rule(1000,0,500L,null)));
    assertEquals(3000,CommissionEngine.commission(100000,rule(1000,0,null,3000L)));
    assertEquals(1000,CommissionEngine.commission(10000,rule(1000,0,500L,3000L)));
  }

  @Test void quoteAddsTheCommissionOnTopOfTheDriverPrice(){
    UUID id=UUID.randomUUID();
    when(db.queryForList(contains("from commission_policy_versions"),any(Object[].class)))
        .thenReturn(List.of(Map.of("id",id,"scope_type","PROFILE","commission_bps",600,"fixed_minor",0L)));
    Quote q=engine.quote(Context.partner(UUID.randomUUID(),"HOTEL"),10000);
    assertEquals(id,q.policyId());
    assertEquals("PROFILE",q.scopeType());
    assertEquals(600,q.commissionMinor());
    assertEquals(10600,q.totalMinor());
  }

  @Test void com02_partnerBookingResolvesOnTheOrganisationNeverOnTheUser(){
    UUID partner=UUID.randomUUID();
    when(db.queryForList(eq(CommissionEngine.RESOLVE_SQL),any(Object[].class)))
        .thenReturn(List.of(Map.of("id",UUID.randomUUID(),"scope_type","PARTNER","commission_bps",500,"fixed_minor",0L)));
    engine.resolve(new Context("PARTNER",UUID.randomUUID(),partner,"HOTEL"));
    // profile, category x2, partner x2, user x2 (user rule ignored for partner bookings)
    verify(db).queryForList(eq(CommissionEngine.RESOLVE_SQL),eq("PARTNER"),eq("HOTEL"),eq("HOTEL"),eq(partner),eq(partner),isNull(),isNull());
  }

  @Test void com01_clientBookingResolvesOnTheUserAndClientProfile(){
    UUID user=UUID.randomUUID();
    when(db.queryForList(eq(CommissionEngine.RESOLVE_SQL),any(Object[].class)))
        .thenReturn(List.of(Map.of("id",UUID.randomUUID(),"scope_type","USER","commission_bps",700,"fixed_minor",0L)));
    engine.resolve(Context.client(user));
    verify(db).queryForList(eq(CommissionEngine.RESOLVE_SQL),eq("CLIENT"),isNull(),isNull(),isNull(),isNull(),eq(user),eq(user));
  }

  @Test void resolutionOrderIsUserPartnerCategoryProfileStandard(){
    String sql=CommissionEngine.RESOLVE_SQL;
    assertTrue(sql.indexOf("'USER' then 0")<sql.indexOf("'PARTNER' then 1"));
    assertTrue(sql.indexOf("'PARTNER' then 1")<sql.indexOf("'PARTNER_CATEGORY' then 2"));
    assertTrue(sql.indexOf("'PARTNER_CATEGORY' then 2")<sql.indexOf("'PROFILE' then 3"));
    assertTrue(sql.contains("effective_from<=now()")&&sql.contains("effective_to>now()"));
  }

  @Test void missingPolicyIsAnExplicitError(){
    when(db.queryForList(contains("from commission_policy_versions"),any(Object[].class))).thenReturn(List.of());
    assertEquals("COMMISSION_POLICY_MISSING",assertThrows(ApiException.class,()->engine.resolve(Context.client(UUID.randomUUID()))).code());
  }
}
