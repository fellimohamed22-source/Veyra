package com.veyra.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Section 34 explicitly requires rate limiting; grepped the whole
 * backend first and confirmed none existed anywhere before this.
 *
 * Deliberately dependency-free (no Bucket4j, no Redis) -- this project
 * doesn't use Redis at all (checked pom.xml/application.yml first), and
 * adding a brand-new Maven dependency carries real, demonstrated risk in
 * this environment: two CI breaks earlier this session both traced back
 * to things that couldn't be verified without Maven/Docker access here.
 * A plain in-memory fixed-window counter per client IP needs nothing
 * beyond the JDK already in use.
 *
 * Scoped only to the handful of genuinely sensitive, UNauthenticated
 * endpoints where brute-force/enumeration/spam is the realistic concern
 * (login, register, forgot/reset password) -- not a general API
 * gateway-style limiter across every route, which this simple approach
 * isn't sized for anyway.
 *
 * NOT a @Component: SecurityConfig's existing jwtFilter is a plain
 * @Bean factory method registered explicitly via
 * .addFilterBefore(...), not @Component -- matching that pattern here
 * deliberately, since a @Component OncePerRequestFilter/Filter bean
 * would also get auto-registered as a generic servlet filter by Spring
 * Boot's own filter auto-configuration, on top of whatever explicit
 * Security-chain registration is added, silently double-applying the
 * rate limit (or applying it somewhere unintended).
 */
public class RateLimitFilter extends OncePerRequestFilter {

  private static final long WINDOW_MS = 60_000;
  private static final int MAX_REQUESTS_PER_WINDOW = 20;

  private static final class Counter {
    volatile long windowStart;
    final AtomicLong count = new AtomicLong();
    Counter(long now){ windowStart = now; }
  }

  private final ConcurrentHashMap<String,Counter> counters = new ConcurrentHashMap<>();

  @Override
  protected boolean shouldNotFilter(HttpServletRequest request){
    String path = request.getRequestURI();
    return !("POST".equalsIgnoreCase(request.getMethod()) && (
        path.equals("/api/v1/auth/login") ||
        path.equals("/api/v1/auth/register") ||
        path.equals("/api/v1/auth/forgot-password") ||
        path.equals("/api/v1/auth/reset-password")));
  }

  @Override
  protected void doFilterInternal(HttpServletRequest request,HttpServletResponse response,FilterChain chain)
      throws ServletException, IOException {
    String key = clientIp(request) + "|" + request.getRequestURI();
    long now = System.currentTimeMillis();
    Counter c = counters.computeIfAbsent(key, k -> new Counter(now));

    long count;
    synchronized (c) {
      if (now - c.windowStart > WINDOW_MS) {
        c.windowStart = now;
        c.count.set(0);
      }
      count = c.count.incrementAndGet();
    }

    if (count > MAX_REQUESTS_PER_WINDOW) {
      response.setStatus(429);
      response.setContentType("application/json");
      // Same shape as ApiExceptionHandler's error body so the mobile/web
      // clients' existing code-based error extraction keeps working
      // without a special case for this filter.
      response.getWriter().write("{\"code\":\"RATE_LIMITED\",\"message\":\"Too many requests, please try again shortly.\"}");
      return;
    }
    chain.doFilter(request,response);
  }

  private String clientIp(HttpServletRequest request){
    String xff = request.getHeader("X-Forwarded-For");
    if (xff != null && !xff.isBlank()) {
      return xff.split(",")[0].trim();
    }
    return request.getRemoteAddr();
  }

  // Unbounded growth guard: without this, every distinct IP that has
  // ever hit a limited endpoint stays in the map forever. Same
  // @Scheduled pattern already used elsewhere in this codebase
  // (NotificationDelivery, BookingMaintenanceScheduler) rather than
  // introducing a new cleanup mechanism.
  @Scheduled(fixedDelay = 300_000)
  void cleanupStaleCounters(){
    long now = System.currentTimeMillis();
    counters.entrySet().removeIf(e -> now - e.getValue().windowStart > WINDOW_MS * 5);
  }
}
