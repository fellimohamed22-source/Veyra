package com.veyra.commission;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.time.OffsetDateTime;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class CommissionRuleControllerTest {
  JdbcTemplate db=mock(JdbcTemplate.class);
  CommissionRuleController controller=new CommissionRuleController(db);
  UUID admin=UUID.randomUUID();

  @BeforeEach void auth(){SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(admin,null,"ROLE_FINANCE"));}
  @AfterEach void clear(){SecurityContextHolder.clearContext();}

  static CommissionRuleController.NewRule rule(String scope,String profile,String category,UUID partner,UUID user,OffsetDateTime from,OffsetDateTime to){
    return new CommissionRuleController.NewRule(scope,profile,category,partner,user,800,0L,null,null,from,to,"Négociation annuelle");
  }

  @Test void scopeAndSubjectMustMatch(){
    assertThrows(ApiException.class,()->CommissionRuleController.validateSubject(rule("USER",null,null,null,null,null,null)));
    assertThrows(ApiException.class,()->CommissionRuleController.validateSubject(rule("STANDARD","CLIENT",null,null,null,null,null)));
    assertThrows(ApiException.class,()->CommissionRuleController.validateSubject(rule("PARTNER",null,"HOTEL",UUID.randomUUID(),null,null,null)));
    assertDoesNotThrow(()->CommissionRuleController.validateSubject(rule("PARTNER_CATEGORY",null,"HOTEL",null,null,null,null)));
    assertDoesNotThrow(()->CommissionRuleController.validateSubject(rule("USER",null,null,null,UUID.randomUUID(),null,null)));
  }

  @Test void boundsMustBeOrdered(){
    var r=new CommissionRuleController.NewRule("STANDARD",null,null,null,null,1000,0L,5000L,1000L,null,null,"x");
    assertEquals("COMMISSION_BOUNDS_INVALID",assertThrows(ApiException.class,()->controller.create(r)).code());
  }

  @Test void com04_overlappingBoundedRuleAtSamePriorityIsRefused(){
    var from=OffsetDateTime.now().plusDays(10);
    Map<String,Object> existing=new HashMap<>();
    existing.put("id",UUID.randomUUID());
    existing.put("effective_from",java.sql.Timestamp.from(from.minusDays(5).toInstant()));
    existing.put("effective_to",java.sql.Timestamp.from(from.plusDays(5).toInstant()));
    when(db.queryForList(contains("and (effective_to is null or effective_to>?)"),any(Object[].class))).thenReturn(List.of(existing));
    var r=rule("PARTNER_CATEGORY",null,"HOTEL",null,null,from,null);
    assertEquals("COMMISSION_RULE_CONFLICT",assertThrows(ApiException.class,()->controller.create(r)).code());
    verify(db,never()).update(contains("insert into commission_policy_versions"),any(Object[].class));
  }

  @Test void newVersionSupersedesTheOpenEndedOneAndIsAudited(){
    var from=OffsetDateTime.now().plusDays(1);
    UUID previous=UUID.randomUUID();
    Map<String,Object> existing=new HashMap<>();
    existing.put("id",previous);
    existing.put("effective_from",java.sql.Timestamp.from(OffsetDateTime.now().minusDays(30).toInstant()));
    existing.put("effective_to",null);
    when(db.queryForList(contains("and (effective_to is null or effective_to>?)"),any(Object[].class))).thenReturn(List.of(existing));
    when(db.queryForObject(contains("coalesce(max(version_no),0)+1"),eq(Integer.class),any(Object[].class))).thenReturn(2);

    var response=controller.create(rule("PARTNER_CATEGORY",null,"HOTEL",null,null,from,null));

    assertEquals(201,response.getStatusCode().value());
    verify(db).update(contains("set effective_to=? where id=?"),eq(from),eq(previous));
    verify(db).update(contains("insert into commission_policy_versions"),any(Object[].class));
    verify(db).update(contains("insert into audit_logs"),eq(admin),eq("COMMISSION_RULE_CREATED"),any(UUID.class),contains("Négociation annuelle"));
  }

  @Test void standardRuleCannotBeDeactivated(){
    UUID id=UUID.randomUUID();
    when(db.queryForList(contains("for update"),eq(id))).thenReturn(List.of(Map.of("scope_type","STANDARD","status","ACTIVE","commission_bps",1000)));
    assertEquals("STANDARD_RULE_CANNOT_BE_DEACTIVATED",
        assertThrows(ApiException.class,()->controller.deactivate(id,new CommissionRuleController.Deactivation("x"))).code());
  }

  @Test void simulationComputesWithoutWriting(){
    UUID partner=UUID.randomUUID();
    when(db.queryForList(contains("select partner_type"),eq(String.class),eq(partner))).thenReturn(List.of("HOTEL"));
    when(db.queryForList(eq(CommissionEngine.RESOLVE_SQL),any(Object[].class)))
        .thenReturn(List.of(Map.of("id",UUID.randomUUID(),"scope_type","PARTNER_CATEGORY","commission_bps",500,"fixed_minor",100L)));

    var result=controller.simulate(new CommissionRuleController.Simulation("PARTNER",null,partner,10000));

    assertEquals(600L,result.get("commissionMinor"));
    assertEquals(10600L,result.get("customerTotalMinor"));
    assertEquals(10000L,result.get("driverNetMinor"));
    verify(db,never()).update(anyString(),any(Object[].class));
  }
}
