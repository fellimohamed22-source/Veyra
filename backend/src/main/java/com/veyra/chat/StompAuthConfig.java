package com.veyra.chat;

import com.veyra.auth.JwtService;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.messaging.*;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.stomp.*;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

import java.util.UUID;
import java.util.regex.*;

@Configuration
public class StompAuthConfig implements WebSocketMessageBrokerConfigurer {
  private static final Pattern BOOKING_TOPIC =
      Pattern.compile("^/topic/bookings/([0-9a-fA-F-]{36})/(chat|location)$");

  private final JwtService jwt;
  private final JdbcTemplate db;

  public StompAuthConfig(JwtService jwt,JdbcTemplate db){
    this.jwt=jwt;
    this.db=db;
  }

  @Override
  public void configureClientInboundChannel(ChannelRegistration registration){
    registration.interceptors(new ChannelInterceptor(){
      @Override
      public Message<?> preSend(Message<?> message,MessageChannel channel){
        StompHeaderAccessor accessor=StompHeaderAccessor.wrap(message);

        if(StompCommand.CONNECT.equals(accessor.getCommand())){
          String header=accessor.getFirstNativeHeader("Authorization");
          if(header==null||!header.startsWith("Bearer ")){
            throw new AccessDeniedException("JWT required");
          }
          UUID userId=jwt.userId(header.substring(7));
          var authorities=db.queryForList(
              "select r.code from roles r join user_roles ur on ur.role_id=r.id where ur.user_id=?",
              String.class,userId)
            .stream()
            .map(role->new SimpleGrantedAuthority("ROLE_"+role))
            .toList();
          accessor.setUser(new UsernamePasswordAuthenticationToken(userId,null,authorities));
        }

        if(StompCommand.SUBSCRIBE.equals(accessor.getCommand())){
          String destination=accessor.getDestination();
          Matcher matcher=destination==null?null:BOOKING_TOPIC.matcher(destination);
          if(matcher!=null&&matcher.matches()){
            if(!(accessor.getUser() instanceof UsernamePasswordAuthenticationToken auth) ||
                !(auth.getPrincipal() instanceof UUID userId)){
              throw new AccessDeniedException("Authenticated user required");
            }
            UUID bookingId=UUID.fromString(matcher.group(1));
            Integer allowed=db.queryForObject(
              "select count(*) from scheduled_bookings sb " +
              "left join drivers d on d.id=sb.selected_driver_id " +
              "left join partner_users pu on pu.partner_id=sb.partner_id and pu.user_id=? and pu.status='ACTIVE' " +
              "where sb.id=? and (sb.creator_user_id=? or d.user_id=? or pu.id is not null)",
              Integer.class,userId,bookingId,userId,userId);
            if(allowed==null||allowed==0){
              throw new AccessDeniedException("Booking topic forbidden");
            }
          }
        }
        return message;
      }
    });
  }
}
