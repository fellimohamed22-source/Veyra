package com.veyra.auth;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.*;
import java.util.*;

@RestController
@RequestMapping("/api/v1/auth")
public class PasswordController {
  private static final Logger log=LoggerFactory.getLogger(PasswordController.class);

  private final JdbcTemplate db;
  private final JavaMailSender mail;
  private final PasswordEncoder encoder;
  private final SecureRandom random=new SecureRandom();

  public PasswordController(JdbcTemplate db,JavaMailSender mail,PasswordEncoder encoder){
    this.db=db;
    this.mail=mail;
    this.encoder=encoder;
  }

  public record Forgot(@Email @NotBlank String email){}
  public record Reset(
      @NotBlank String token,
      @NotBlank @Size(min=10,max=128) String newPassword){}

  @PostMapping("/forgot-password")
  @Transactional
  public ResponseEntity<Void> forgot(@Valid @RequestBody Forgot request){
    String email=request.email().trim().toLowerCase(Locale.ROOT);
    List<UUID> users=db.queryForList(
        "select id from users where email=? and status='ACTIVE'",
        UUID.class,email);

    if(!users.isEmpty()){
      UUID userId=users.getFirst();
      db.update(
          "update password_reset_tokens set consumed_at=now() " +
          "where user_id=? and consumed_at is null",
          userId);

      String token=token();
      db.update(
          "insert into password_reset_tokens(user_id,token_hash,expires_at) values (?,?,?)",
          userId,sha(token),OffsetDateTime.now().plusMinutes(30));

      SimpleMailMessage message=new SimpleMailMessage();
      message.setTo(email);
      message.setSubject("Veyra — Réinitialisation du mot de passe");
      message.setText("Utilisez ce jeton pendant 30 minutes : "+token);
      try{
        mail.send(message);
      }catch(Exception exception){
        log.error("Password reset email delivery failed userId={}",userId,exception);
      }
    }

    // Always return the same response to avoid email enumeration.
    return ResponseEntity.accepted().build();
  }

  @PostMapping("/reset-password")
  @Transactional
  public ResponseEntity<Void> reset(@Valid @RequestBody Reset request){
    List<Map<String,Object>> rows=db.queryForList(
        "select id,user_id from password_reset_tokens " +
        "where token_hash=? and consumed_at is null and expires_at>now() for update",
        sha(request.token()));
    if(rows.isEmpty()){
      return ResponseEntity.badRequest().build();
    }

    UUID tokenId=(UUID)rows.getFirst().get("id");
    UUID userId=(UUID)rows.getFirst().get("user_id");

    db.update(
        "update users set password_hash=?,failed_login_attempts=0,locked_until=null,updated_at=now() where id=?",
        encoder.encode(request.newPassword()),userId);
    db.update(
        "update password_reset_tokens set consumed_at=now() where id=?",
        tokenId);
    db.update(
        "update user_sessions set revoked_at=now() where user_id=? and revoked_at is null",
        userId);

    return ResponseEntity.noContent().build();
  }

  private String token(){
    byte[] bytes=new byte[32];
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
}
