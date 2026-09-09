package com.veyra.security;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Section 34 explicitly requires rate limiting; none existed anywhere in
 * this backend before RateLimitFilter (see that class's own comment for
 * why it's a dependency-free, in-memory implementation rather than
 * Bucket4j/Redis).
 */
class RateLimitFilterTest {

  private RateLimitFilter filter(){
    return new RateLimitFilter();
  }

  @Test
  void onlyAppliesToTheFourSensitiveUnauthenticatedPostEndpoints() throws Exception {
    RateLimitFilter f = filter();
    MockHttpServletRequest getReq = new MockHttpServletRequest("GET","/api/v1/bookings");
    assertTrue(invokeShouldNotFilter(f,getReq),"GET requests must never be rate-limited by this filter");

    MockHttpServletRequest otherPost = new MockHttpServletRequest("POST","/api/v1/bookings");
    assertTrue(invokeShouldNotFilter(f,otherPost),"unrelated POST endpoints must not be rate-limited");

    MockHttpServletRequest login = new MockHttpServletRequest("POST","/api/v1/auth/login");
    assertFalse(invokeShouldNotFilter(f,login),"login must be rate-limited");
  }

  @Test
  void blocksOnlyAfterExceedingTheWindowLimitForTheSameIpAndPath() throws Exception {
    RateLimitFilter f = filter();
    String ip = "203.0.113.7";

    int lastStatus = 200;
    for (int i = 0; i < 25; i++) {
      MockHttpServletRequest req = new MockHttpServletRequest("POST","/api/v1/auth/login");
      req.setRemoteAddr(ip);
      MockHttpServletResponse res = new MockHttpServletResponse();
      MockFilterChain chain = new MockFilterChain();
      f.doFilter(req,res,chain);
      lastStatus = res.getStatus();
    }

    assertEquals(429,lastStatus,"the 21st+ request within the same 60s window must be rejected (limit is 20)");
  }

  @Test
  void scopesTheCounterPerClientIpNotGlobally() throws Exception {
    RateLimitFilter f = filter();

    // Exhaust the limit for one IP.
    for (int i = 0; i < 20; i++) {
      MockHttpServletRequest req = new MockHttpServletRequest("POST","/api/v1/auth/login");
      req.setRemoteAddr("203.0.113.7");
      f.doFilter(req,new MockHttpServletResponse(),new MockFilterChain());
    }

    // A different IP must still be allowed through -- this is a per-IP
    // limiter, not a global one that would let a single abusive client
    // lock out every other user of the same endpoint.
    MockHttpServletRequest otherIp = new MockHttpServletRequest("POST","/api/v1/auth/login");
    otherIp.setRemoteAddr("198.51.100.42");
    MockHttpServletResponse res = new MockHttpServletResponse();
    f.doFilter(otherIp,res,new MockFilterChain());

    assertNotEquals(429,res.getStatus());
  }

  @Test
  void prefersXForwardedForOverRemoteAddrWhenPresent() throws Exception {
    // Render (this project's deployment target) sits the app behind a
    // proxy -- request.getRemoteAddr() alone would be the proxy's own
    // address for every request, collapsing every real client into one
    // shared counter.
    RateLimitFilter f = filter();
    var m = RateLimitFilter.class.getDeclaredMethod("clientIp",jakarta.servlet.http.HttpServletRequest.class);
    m.setAccessible(true);

    MockHttpServletRequest withProxy = new MockHttpServletRequest();
    withProxy.setRemoteAddr("10.0.0.1");
    withProxy.addHeader("X-Forwarded-For","203.0.113.99, 10.0.0.1");
    assertEquals("203.0.113.99",m.invoke(f,withProxy));

    MockHttpServletRequest direct = new MockHttpServletRequest();
    direct.setRemoteAddr("203.0.113.50");
    assertEquals("203.0.113.50",m.invoke(f,direct));
  }

  private boolean invokeShouldNotFilter(RateLimitFilter f, MockHttpServletRequest req) throws Exception {
    var m = RateLimitFilter.class.getDeclaredMethod("shouldNotFilter",jakarta.servlet.http.HttpServletRequest.class);
    m.setAccessible(true);
    return (boolean) m.invoke(f,req);
  }
}
