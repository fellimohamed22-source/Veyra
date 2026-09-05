package com.veyra.security;

import com.veyra.auth.JwtService;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.*;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.*;
import java.util.UUID;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {

  @Bean
  PasswordEncoder encoder() {
    return new BCryptPasswordEncoder(12);
  }

  @Bean
  CorsConfigurationSource corsConfigurationSource(
      @Value("${veyra.websocket.allowed-origins:http://localhost:4200,http://localhost:8080}") String origins) {
    CorsConfiguration configuration = new CorsConfiguration();
    configuration.setAllowedOriginPatterns(Arrays.stream(origins.split(","))
        .map(String::trim)
        .filter(value -> !value.isBlank())
        .toList());
    configuration.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
    configuration.setAllowedHeaders(List.of(
        "Authorization",
        "Content-Type",
        "Idempotency-Key",
        "Stripe-Signature",
        "X-Requested-With"));
    configuration.setExposedHeaders(List.of("Location"));
    configuration.setAllowCredentials(true);
    configuration.setMaxAge(3600L);

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/api/**", configuration);
    source.registerCorsConfiguration("/actuator/**", configuration);
    return source;
  }

  @Bean
  OncePerRequestFilter jwtFilter(JwtService jwt, JdbcTemplate jdbc) {
    return new OncePerRequestFilter() {
      @Override
      protected void doFilterInternal(
          HttpServletRequest request,
          HttpServletResponse response,
          FilterChain chain) throws ServletException, IOException {

        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) {
          try {
            UUID userId = jwt.userId(header.substring(7));
            var authorities = jdbc.queryForList(
                    "select r.code from roles r join user_roles ur on ur.role_id=r.id where ur.user_id=?",
                    String.class,
                    userId)
                .stream()
                .map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .toList();
            SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(userId, null, authorities));
          } catch (Exception ignored) {
            SecurityContextHolder.clearContext();
          }
        }
        chain.doFilter(request, response);
      }
    };
  }

  @Bean
  SecurityFilterChain chain(
      HttpSecurity http,
      OncePerRequestFilter jwtFilter,
      CorsConfigurationSource corsConfigurationSource) throws Exception {
    return http
        .csrf(csrf -> csrf.disable())
        .cors(cors -> cors.configurationSource(corsConfigurationSource))
        .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
        .authorizeHttpRequests(auth -> auth
            .requestMatchers(
                "/api/v1/auth/**",
                "/api/v1/payments/stripe/webhook",
                "/actuator/health")
            .permitAll()
            .anyRequest()
            .authenticated())
        .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
        .build();
  }
}
