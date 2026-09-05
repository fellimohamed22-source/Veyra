package com.veyra.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import jakarta.annotation.PostConstruct;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

@Component
@Profile("prod")
public class ProductionConfigValidator {
  private final String jwtSecret;
  private final String pinKey;
  private final String allowedOrigins;
  private final String databaseUrl;

  public ProductionConfigValidator(
      @Value("${veyra.jwt.secret}") String jwtSecret,
      @Value("${veyra.crypto.pin-key}") String pinKey,
      @Value("${veyra.websocket.allowed-origins}") String allowedOrigins,
      @Value("${spring.datasource.url}") String databaseUrl){
    this.jwtSecret=jwtSecret;
    this.pinKey=pinKey;
    this.allowedOrigins=allowedOrigins;
    this.databaseUrl=databaseUrl;
  }

  @PostConstruct
  public void validate(){
    if(jwtSecret==null || jwtSecret.getBytes(StandardCharsets.UTF_8).length<32 ||
        jwtSecret.startsWith("dev-only") || jwtSecret.startsWith("local-")){
      throw new IllegalStateException("Production JWT secret is missing or unsafe");
    }
    if(pinKey==null || pinKey.getBytes(StandardCharsets.UTF_8).length<32 ||
        pinKey.startsWith("dev-") || pinKey.startsWith("local-")){
      throw new IllegalStateException("Production PIN encryption key is missing or unsafe");
    }
    if(databaseUrl==null || databaseUrl.contains("localhost")){
      throw new IllegalStateException("Production database URL must be explicitly configured");
    }
    if(allowedOrigins==null || allowedOrigins.isBlank() ||
        Arrays.stream(allowedOrigins.split(","))
            .map(String::trim)
            .anyMatch(origin->origin.isBlank() || origin.contains("localhost") || "*".equals(origin))){
      throw new IllegalStateException("Production allowed origins must be explicit HTTPS application origins");
    }
  }
}
