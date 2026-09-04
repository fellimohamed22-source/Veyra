package com.veyra.auth;

import com.veyra.shared.ApiException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.OffsetDateTime;
import java.util.*;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {
  private final UserRepository users;
  private final PasswordEncoder encoder;
  private final JwtService jwt;
  private final JdbcTemplate db;
  private final SecureRandom random=new SecureRandom();

  public AuthController(
      UserRepository users,
      PasswordEncoder encoder,
      JwtService jwt,
      JdbcTemplate db){
    this.users=users;
    this.encoder=encoder;
    this.jwt=jwt;
    this.db=db;
  }

  public record Register(
      @Email @NotBlank String email,
      @Size(min=10,max=128) String password,
      @NotBlank @Size(max=100) String firstName,
      @Size(max=100) String lastName,
      @Size(max=32) String phone){}

  public record Login(
      @Email @NotBlank String email,
      @NotBlank String password,
      String deviceName){}

  public record Tokens(
      String accessToken,
      String refreshToken,
      UUID userId){}

  @PostMapping("/register")
  @Transactional
  public ResponseEntity<Tokens> register(@Valid @RequestBody Register request){
    String email=request.email().trim().toLowerCase(Locale.ROOT);
    if(users.existsByEmailIgnoreCase(email)){
      throw new ApiException(HttpStatus.CONFLICT,"EMAIL_ALREADY_USED");
    }

    User user=users.save(new User(
        request.firstName().trim(),
        request.lastName()==null?null:request.lastName().trim(),
        email,
        encoder.encode(request.password())));

    if(request.phone()!=null && !request.phone().isBlank()){
      db.update("update users set phone=? where id=?",request.phone().trim(),user.id());
    }

    db.update(
        "insert into user_roles(user_id,role_id) select ?,id from roles where code='CLIENT' on conflict do nothing",
        user.id());

    return ResponseEntity.status(HttpStatus.CREATED).body(tokens(user,"registration"));
  }

  @PostMapping("/login")
  @Transactional
  public Tokens login(@Valid @RequestBody Login request){
    User user=users.findByEmailIgnoreCase(request.email().trim())
        .orElseThrow(()->new ApiException(HttpStatus.UNAUTHORIZED,"INVALID_CREDENTIALS"));

    if(user.lockedUntil()!=null && user.lockedUntil().isAfter(OffsetDateTime.now())){
      throw new ApiException(HttpStatus.LOCKED,"ACCOUNT_LOCKED");
    }

    if(!encoder.matches(request.password(),user.passwordHash())){
      user.failed();
      users.save(user);
      throw new ApiException(HttpStatus.UNAUTHORIZED,"INVALID_CREDENTIALS");
    }

    if(!"ACTIVE".equals(user.status())){
      throw new ApiException(HttpStatus.FORBIDDEN,"ACCOUNT_NOT_ACTIVE");
    }

    user.success();
    users.save(user);
    return tokens(user,request.deviceName());
  }

  private Tokens tokens(User user,String deviceName){
    List<String> roles=db.queryForList(
        "select r.code from roles r join user_roles ur on ur.role_id=r.id where ur.user_id=?",
        String.class,
        user.id());

    String access=jwt.issue(user.id(),user.email(),roles);
    byte[] bytes=new byte[48];
    random.nextBytes(bytes);
    String refresh=Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);

    db.update(
        "insert into user_sessions(user_id,refresh_token_hash,device_name,expires_at) values (?,?,?,?)",
        user.id(),
        sha256(refresh),
        deviceName,
        OffsetDateTime.now().plusDays(30));

    return new Tokens(access,refresh,user.id());
  }

  private String sha256(String value){
    try{
      return HexFormat.of().formatHex(
          MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
    }catch(NoSuchAlgorithmException e){
      throw new IllegalStateException(e);
    }
  }
}
