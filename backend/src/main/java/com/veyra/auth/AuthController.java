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

  public record FirebaseLogin(
      @NotBlank String idToken,
      @Pattern(regexp="CLIENT|DRIVER") String role,
      String deviceName){}

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

  @PostMapping("/register-driver")
  @Transactional
  public ResponseEntity<Tokens> registerDriver(@Valid @RequestBody Register request){
    String email=request.email().trim().toLowerCase(Locale.ROOT);
    if(users.existsByEmailIgnoreCase(email))throw new ApiException(HttpStatus.CONFLICT,"EMAIL_ALREADY_USED");
    if(request.phone()==null||request.phone().trim().length()<6)throw new ApiException(HttpStatus.BAD_REQUEST,"PHONE_REQUIRED");
    User user=users.save(new User(request.firstName().trim(),request.lastName()==null?null:request.lastName().trim(),email,encoder.encode(request.password())));
    db.update("update users set phone=? where id=?",request.phone().trim(),user.id());
    db.update("insert into user_roles(user_id,role_id) select ?,id from roles where code='DRIVER' on conflict do nothing",user.id());
    db.update("insert into drivers(id,user_id) values (?,?)",UUID.randomUUID(),user.id());
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
    String phone=Objects.toString(claims.get("phone_number"),"").trim();
    String role=request.role()==null?"CLIENT":request.role();
    User user=null;
    if(!email.isEmpty())user=users.findByEmailIgnoreCase(email).orElse(null);
    if(user==null&&!phone.isEmpty()){
      List<UUID> ids=db.queryForList("select id from users where phone=?",UUID.class,phone);
      if(!ids.isEmpty())user=users.findById(ids.getFirst()).orElse(null);
    }
    if(user==null){
      if(email.isEmpty())email="firebase-"+firebaseUid+"@phone.veyra.local";
      String name=Objects.toString(claims.get("name"),role.equals("DRIVER")?"Chauffeur Veyra":"Client Veyra").trim();
      if(name.isEmpty())name=role.equals("DRIVER")?"Chauffeur Veyra":"Client Veyra";
      user=users.save(new User(name,null,email,encoder.encode(UUID.randomUUID().toString()+UUID.randomUUID())));
      if(!phone.isEmpty())db.update("update users set phone=? where id=?",phone,user.id());
    }
    db.update("insert into user_roles(user_id,role_id) select ?,id from roles where code=? on conflict do nothing",user.id(),role);
    if("DRIVER".equals(role)){
      Integer count=db.queryForObject("select count(*) from drivers where user_id=?",Integer.class,user.id());
      if(count==null||count==0)db.update("insert into drivers(id,user_id) values (?,?)",UUID.randomUUID(),user.id());
    }
    return tokens(user,request.deviceName()==null?provider+"-mobile":request.deviceName());
  }

  @SuppressWarnings("unchecked")
  private Map<String,Object> verifyFirebaseIdToken(String idToken){
    try{
      String[] parts=idToken.split("\\.");
      if(parts.length!=3)throw new ApiException(HttpStatus.UNAUTHORIZED,"FIREBASE_TOKEN_INVALID");
      Map<String,Object> header=new com.fasterxml.jackson.databind.ObjectMapper().readValue(
          Base64.getUrlDecoder().decode(parts[0]),Map.class);
      if(!"RS256".equals(header.get("alg")))throw new ApiException(HttpStatus.UNAUTHORIZED,"FIREBASE_TOKEN_INVALID");
      String kid=Objects.toString(header.get("kid"),"");
      if(kid.isEmpty())throw new ApiException(HttpStatus.UNAUTHORIZED,"FIREBASE_TOKEN_INVALID");
      java.net.http.HttpClient http=java.net.http.HttpClient.newBuilder().connectTimeout(java.time.Duration.ofSeconds(5)).build();
      var req=java.net.http.HttpRequest.newBuilder(java.net.URI.create("https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"))
          .timeout(java.time.Duration.ofSeconds(8)).GET().build();
      var resp=http.send(req,java.net.http.HttpResponse.BodyHandlers.ofString());
      if(resp.statusCode()!=200)throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"FIREBASE_KEYS_UNAVAILABLE");
      Map<String,String> certs=new com.fasterxml.jackson.databind.ObjectMapper().readValue(resp.body(),Map.class);
      String pem=certs.get(kid);
      if(pem==null)throw new ApiException(HttpStatus.UNAUTHORIZED,"FIREBASE_TOKEN_INVALID");
      String clean=pem.replace("-----BEGIN CERTIFICATE-----","").replace("-----END CERTIFICATE-----","").replaceAll("\\s","");
      var cert=(java.security.cert.X509Certificate)java.security.cert.CertificateFactory.getInstance("X.509")
          .generateCertificate(new java.io.ByteArrayInputStream(Base64.getDecoder().decode(clean)));
      java.security.Signature signature=java.security.Signature.getInstance("SHA256withRSA");
      signature.initVerify(cert.getPublicKey());
      signature.update((parts[0]+"."+parts[1]).getBytes(StandardCharsets.UTF_8));
      if(!signature.verify(Base64.getUrlDecoder().decode(parts[2])))throw new ApiException(HttpStatus.UNAUTHORIZED,"FIREBASE_TOKEN_INVALID");
      Map<String,Object> claims=new com.fasterxml.jackson.databind.ObjectMapper().readValue(Base64.getUrlDecoder().decode(parts[1]),Map.class);
      long now=System.currentTimeMillis()/1000L;
      long exp=((Number)claims.getOrDefault("exp",0)).longValue();
      long iat=((Number)claims.getOrDefault("iat",0)).longValue();
      String aud=Objects.toString(claims.get("aud"),"");
      String iss=Objects.toString(claims.get("iss"),"");
      String project=iss.startsWith("https://securetoken.google.com/")?iss.substring("https://securetoken.google.com/".length()):"";
      if(project.isEmpty()||!project.equals(aud)||exp<=now||iat>now+60)throw new ApiException(HttpStatus.UNAUTHORIZED,"FIREBASE_TOKEN_INVALID");
      Object firebase=claims.get("firebase");
      if(firebase instanceof Map<?,?> fm)claims.put("provider",Objects.toString(fm.get("sign_in_provider"),"firebase"));
      return claims;
    }catch(ApiException e){throw e;}
    catch(Exception e){throw new ApiException(HttpStatus.UNAUTHORIZED,"FIREBASE_TOKEN_INVALID");}
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
