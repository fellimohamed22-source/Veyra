package com.veyra.chat;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.web.socket.config.annotation.*;

@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {
  private final String[] allowedOrigins;

  public WebSocketConfig(
      @Value("${veyra.websocket.allowed-origins:http://localhost:4200,http://localhost:8080}") String origins){
    this.allowedOrigins=java.util.Arrays.stream(origins.split(","))
      .map(String::trim)
      .filter(value->!value.isBlank())
      .toArray(String[]::new);
  }

  @Override
  public void configureMessageBroker(MessageBrokerRegistry registry){
    registry.enableSimpleBroker("/topic","/queue");
    registry.setApplicationDestinationPrefixes("/app");
  }

  @Override
  public void registerStompEndpoints(StompEndpointRegistry registry){
    registry.addEndpoint("/ws").setAllowedOriginPatterns(allowedOrigins);
  }
}
