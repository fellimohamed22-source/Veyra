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
  private final String firebaseProjectId;
  private final ConsentService consents;
  private final SecureRandom random=new SecureRandom();

  public AuthController(
      UserRepository users,
      PasswordEncoder encoder,
      JwtService jwt,
      JdbcTemplate db,
      @org.springframework.beans.factory.annotation.Value("${veyra.firebase.project-id}") String firebaseProjectId,
      ConsentService consents){
    this.users=users;
    this.encoder=encoder;
    this.jwt=jwt;
    this.db=db;
    this.firebaseProjectId=firebaseProjectId==null?"":firebaseProjectId.trim();
    this.consents=consents;
  }

  public record Register(
      @Email @NotBlank String email,
      @Size(min=10,max=128) String password,
      @NotBlank @Size(max=100) String firstName,
      @Size(max=100) String lastName,
      @Size(max=32) String phone,
      Boolean acceptTerms,
      Boolean acceptPrivacy,
      Boolean marketingOptIn){}

  public record Login(
      @Email @NotBlank String email,
      @NotBlank String password,
      String deviceName){}

  public record Tokens(
      String accessToken,
      String refreshToken,
      UUID userId){}

  public record FirebaseLogin(
      @NotBlank String idToken,
      @Pattern(regexp="CLIENT|DRIVER") String role,
      String deviceName){}

  @PostMapping("/register")
  @Transactional
  public ResponseEntity<Tokens> register(@Valid @RequestBody Register request){
    ConsentService.requireMandatory(request.acceptTerms(),request.acceptPrivacy());
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

    consents.recordSignup(user.id(),Boolean.TRUE.equals(request.marketingOptIn()),"SIGNUP_CLIENT");
    return ResponseEntity.status(HttpStatus.CREATED).body(tokens(user,"registration"));
  }

  @PostMapping("/register-driver")
  @Transactional
  public ResponseEntity<Tokens> registerDriver(@Valid @RequestBody Register request){
    ConsentService.requireMandatory(request.acceptTerms(),request.acceptPrivacy());
    String email=request.email().trim().toLowerCase(Locale.ROOT);
    if(users.existsByEmailIgnoreCase(email))throw new ApiException(HttpStatus.CONFLICT,"EMAIL_ALREADY_USED");
    if(request.phone()==null||request.phone().trim().length()<6)throw new ApiException(HttpStatus.BAD_REQUEST,"PHONE_REQUIRED");
    User user=users.save(new User(request.firstName().trim(),request.lastName()==null?null:request.lastName().trim(),email,encoder.encode(request.password())));
    db.update("update users set phone=? where id=?",request.phone().trim(),user.id());
    db.update("insert into user_roles(user_id,role_id) select ?,id from roles where code='DRIVER' on conflict do nothing",user.id());
    db.update("insert into drivers(id,user_id) values (?,?)",UUID.randomUUID(),user.id());
    consents.recordSignup(user.id(),Boolean.TRUE.equals(request.marketingOptIn()),"SIGNUP_DRIVER");
    return ResponseEntity.status(HttpStatus.CREATED).body(tokens(user,"driver-registration"));
  }

  @PostMapping("/firebase")
  @Transactional
  public Tokens firebase(@Valid @RequestBody FirebaseLogin request){
    Map<String,Object> claims=verifyFirebaseIdToken(request.idToken());
    String firebaseUid=Objects.toString(claims.get("user_id"),Objects.toString(claims.get("sub"),"")).trim();
    if(firebaseUid.isEmpty())throw new ApiException(HttpStatus.UNAUTHORIZED,"FIREBASE_TOKEN_INVALID");
    String provider=Objects.toString(claims.get("provider"),"").trim();
    String email=Objects.toString(claims.get("email"),"").trim().toLowerCase(Locale.ROOT);
    boolean emailVerified=Boolean.TRUE.equals(claims.get("email_verified"));
    String phone=Objects.toString(claims.get("phone_number"),"").trim();
    // A phone_number claim is only proven by Firebase when the sign-in
    // itself was an SMS verification; other providers may carry an
    // unverified, user-supplied number.
    boolean phoneVerified="phone".equals(provider)&&!phone.isEmpty();
    String role=request.role()==null?"CLIENT":request.role();
    User user=null;
    List<UUID> bound=db.queryForList("select id from users where firebase_uid=?",UUID.class,firebaseUid);
    if(!bound.isEmpty())user=users.findById(bound.getFirst()).orElse(null);
    if(user==null&&!email.isEmpty()){
      User byEmail=users.findByEmailIgnoreCase(email).orElse(null);
      if(byEmail!=null){
        // Linking an existing VEYRA account to a Firebase identity is only
        // safe when Firebase has proven ownership of that email; otherwise
        // anyone could register the victim's address on Firebase first.
        if(!emailVerified)throw new ApiException(HttpStatus.CONFLICT,"FIREBASE_EMAIL_NOT_VERIFIED");
        user=byEmail;
      }
    }
    if(user==null&&phoneVerified){
      List<UUID> ids=db.queryForList("select id from users where phone=?",UUID.class,phone);
      if(!ids.isEmpty())user=users.findById(ids.getFirst()).orElse(null);
    }
    if(user==null){
      if(email.isEmpty())email="firebase-"+firebaseUid+"@phone.veyra.local";
      String name=Objects.toString(claims.get("name"),role.equals("DRIVER")?"Chauffeur Veyra":"Client Veyra").trim();
      if(name.isEmpty())name=role.equals("DRIVER")?"Chauffeur Veyra":"Client Veyra";
      user=users.save(new User(name,null,email,encoder.encode(UUID.randomUUID().toString()+UUID.randomUUID())));
      if(phoneVerified)db.update("update users set phone=? where id=?",phone,user.id());
    }
    if(!"ACTIVE".equals(user.status()))throw new ApiException(HttpStatus.FORBIDDEN,"ACCOUNT_NOT_ACTIVE");
    // Bind only an unbound account: a row already bound to another uid is
    // never re-pointed (unique index enforces one account per identity).
    db.update("update users set firebase_uid=? where id=? and firebase_uid is null",firebaseUid,user.id());
    db.update("insert into user_roles(user_id,role_id) select ?,id from roles where code=? on conflict do nothing",user.id(),role);
    if("DRIVER".equals(role)){
      Integer count=db.queryForObject("select count(*) from drivers where user_id=?",Integer.class,user.id());
      if(count==null||count==0)db.update("insert into drivers(id,user_id) values (?,?)",UUID.randomUUID(),user.id());
    }
    return tokens(user,request.deviceName()==null?provider+"-mobile":request.deviceName());
  }

  Map<String,Object> verifyFirebaseIdToken(String idToken){
    return FirebaseIdTokens.verify(idToken,firebaseProjectId);
  }

  static void validateFirebaseClaims(Map<String,Object> claims,String expectedProjectId,long nowEpochSeconds){
    FirebaseIdTokens.validateClaims(claims,expectedProjectId,nowEpochSeconds);
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
