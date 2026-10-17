package com.veyra.payment;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** DEC-04: card saved on the user's Stripe customer and reused at the next booking. */
class SavedCardTest {
  JdbcTemplate db=mock(JdbcTemplate.class);
  StripePaymentService stripe=mock(StripePaymentService.class);
  StripePaymentController controller=new StripePaymentController(db,stripe);
  UUID user=UUID.randomUUID();

  @BeforeEach void auth(){SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(user,null));}
  @AfterEach void clear(){SecurityContextHolder.clearContext();}

  @Test void firstPaymentCreatesTheStripeCustomerOnceAndStoresOnlyItsReference() throws Exception {
    when(db.queryForList(contains("from payment_customers"),eq(String.class),eq(user))).thenReturn(List.of());
    when(db.queryForList(contains("from users"),eq(String.class),eq(user))).thenReturn(List.of("client@example.com"));
    when(stripe.createCustomer(user.toString(),"client@example.com")).thenReturn("cus_123");
    when(db.queryForObject(contains("select provider_customer_id from payment_customers"),eq(String.class),eq(user))).thenReturn("cus_123");

    assertEquals("cus_123",controller.customerId());
    verify(db).update(contains("insert into payment_customers"),eq(user),eq("cus_123"));
  }

  @Test void existingCustomerIsReusedWithoutCallingStripe() throws Exception {
    when(db.queryForList(contains("from payment_customers"),eq(String.class),eq(user))).thenReturn(List.of("cus_123"));
    assertEquals("cus_123",controller.customerId());
    verify(stripe,never()).createCustomer(any(),any());
  }

  @Test void savedCardsAreListedFromTheUsersOwnCustomerOnly() throws Exception {
    when(db.queryForList(contains("from payment_customers"),eq(String.class),eq(user))).thenReturn(List.of("cus_123"));
    when(stripe.savedCards("cus_123")).thenReturn(List.of(Map.of("id","pm_1","brand","visa","last4","4242")));
    assertEquals("4242",controller.savedCards().getFirst().get("last4"));
  }

  @Test void userWithoutCustomerHasNoSavedCards() throws Exception {
    when(db.queryForList(contains("from payment_customers"),eq(String.class),eq(user))).thenReturn(List.of());
    assertTrue(controller.savedCards().isEmpty());
    verify(stripe,never()).savedCards(any());
  }

  @Test void removingACardIsScopedToTheUsersCustomerAndValidatesTheId() throws Exception {
    assertEquals("INVALID_PAYMENT_METHOD",assertThrows(ApiException.class,()->controller.removeCard("../cus_other")).code());
    when(db.queryForList(contains("from payment_customers"),eq(String.class),eq(user))).thenReturn(List.of("cus_123"));
    controller.removeCard("pm_abc");
    verify(stripe).detachCard("cus_123","pm_abc");
  }
}
