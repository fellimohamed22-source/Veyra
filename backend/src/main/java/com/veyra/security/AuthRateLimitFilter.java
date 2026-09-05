package com.veyra.security;

import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Duration;
import java.util.Map;

@Component
public class AuthRateLimitFilter extends OncePerRequestFilter {
  private final StringRedisTemplate redis;
  private final int loginLimit;
  private final int sensitiveLimit;

  public AuthRateLimitFilter(
      StringRedisTemplate redis,
      @Value("${veyra.security.rate-limit.login-per-minute:20}") int loginLimit,
      @Value("${veyra.security.rate-limit.sensitive-per-hour:10}") int sensitiveLimit){
    this.redis=redis;
    this.loginLimit=loginLimit;
    this.sensitiveLimit=sensitiveLimit;
  }

  @Override
  protected boolean shouldNotFilter(HttpServletRequest request){
    if(!"POST".equalsIgnoreCase(request.getMethod())) return true;
    String path=request.getRequestURI();
    return !Map.of(
        "/api/v1/auth/login","login",
        "/api/v1/auth/register","register",
        "/api/v1/auth/forgot-password","forgot",
        "/api/v1/auth/reset-password","reset")
        .containsKey(path);
  }

  @Override
  protected void doFilterInternal(
      HttpServletRequest request,
      HttpServletResponse response,
      FilterChain chain) throws ServletException, IOException {
    String path=request.getRequestURI();
    boolean login="/api/v1/auth/login".equals(path);
    int limit=login?loginLimit:sensitiveLimit;
    Duration window=login?Duration.ofMinutes(1):Duration.ofHours(1);
    String bucket=login?"login":"sensitive";
    String client=request.getRemoteAddr()==null?"unknown":request.getRemoteAddr();
    long slot=System.currentTimeMillis()/window.toMillis();
    String key="veyra:rate:"+bucket+":"+client+":"+slot;

    try{
      Long count=redis.opsForValue().increment(key);
      if(count!=null && count==1L) redis.expire(key,window.plusMinutes(1));
      if(count!=null && count>limit){
        response.setStatus(429);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.getWriter().write("{\"code\":\"RATE_LIMITED\"}");
        return;
      }
    }catch(Exception ignored){
      // Fail open: authentication remains available if Redis is temporarily unavailable.
    }

    chain.doFilter(request,response);
  }
}
