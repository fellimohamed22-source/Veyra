package com.veyra.auth;

import com.veyra.shared.ApiException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.*;
import java.util.*;

@RestController
@RequestMapping("/api/v1/auth")
public class SessionController {
  private final JdbcTemplate db;
  private final JwtService jwt;
  private final SecureRandom random=new SecureRandom();

  public SessionController(JdbcTemplate db,JwtService jwt){
    this.db=db;
    this.jwt=jwt;
  }

  public record Req(
      @NotBlank String refreshToken,
      @Size(max=255) String deviceName){}
  public record Resp(String accessToken,String refreshToken,UUID userId){}

  @PostMapping("/refresh")
  @Transactional
  public Resp refresh(@Valid @RequestBody Req request){
    String hash=sha(request.refreshToken());
    List<Map<String,Object>> sessions=db.queryForList(
        "select s.id,s.user_id,u.email from user_sessions s " +
        "join users u on u.id=s.user_id " +
        "where s.refresh_token_hash=? and s.revoked_at is null and s.expires_at>now() " +
        "and u.status='ACTIVE' for update",
        hash);

    if(sessions.isEmpty()){
      throw new ApiException(HttpStatus.UNAUTHORIZED,"INVALID_REFRESH_TOKEN");
    }

    Map<String,Object> session=sessions.getFirst();
    UUID sessionId=(UUID)session.get("id");
    UUID userId=(UUID)session.get("user_id");

    int revoked=db.update(
        "update user_sessions set revoked_at=now() where id=? and revoked_at is null",
        sessionId);
    if(revoked!=1){
      throw new ApiException(HttpStatus.UNAUTHORIZED,"INVALID_REFRESH_TOKEN");
    }

    List<String> roles=db.queryForList(
        "select r.code from roles r join user_roles ur on ur.role_id=r.id where ur.user_id=?",
        String.class,userId);

    String fresh=token();
    db.update(
        "insert into user_sessions(user_id,refresh_token_hash,device_name,expires_at) values (?,?,?,?)",
        userId,sha(fresh),trim(request.deviceName()),OffsetDateTime.now().plusDays(30));

    return new Resp(
        jwt.issue(userId,(String)session.get("email"),roles),
        fresh,
        userId);
  }

  @PostMapping("/logout")
  @Transactional
  public ResponseEntity<Void> logout(@Valid @RequestBody Req request){
    db.update(
        "update user_sessions set revoked_at=now() where refresh_token_hash=? and revoked_at is null",
        sha(request.refreshToken()));
    return ResponseEntity.noContent().build();
  }

  private String token(){
    byte[] bytes=new byte[48];
    random.nextBytes(bytes);
    return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
  }

  private String sha(String value){
    try{
      return HexFormat.of().formatHex(
          MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
    }catch(NoSuchAlgorithmException exception){
      throw new IllegalStateException(exception);
    }
  }

  private String trim(String value){
    return value==null?null:value.trim();
  }
}
