package com.veyra.auth;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.lang.reflect.Field;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * V4 acceptance scenarios AUTH-01 (token from another Firebase project)
 * and AUTH-02 (no account takeover through an unverified email). The
 * RSA signature check needs Google's live certificates, so these tests
 * stub verifyFirebaseIdToken and exercise claim validation and account
 * resolution, which is where the takeover lived.
 */
@ExtendWith(MockitoExtension.class)
class FirebaseLoginSecurityTest {
  static final String PROJECT="veyra-4806a";
  static final long NOW=1_800_000_000L;

  @Mock UserRepository users;
  @Mock PasswordEncoder encoder;
  @Mock JwtService jwt;
  @Mock JdbcTemplate db;

  static Map<String,Object> claims(String project,String sub){
    Map<String,Object> c=new HashMap<>();
    c.put("aud",project);
    c.put("iss","https://securetoken.google.com/"+project);
    c.put("sub",sub);
    c.put("user_id",sub);
    c.put("exp",NOW+3600);
    c.put("iat",NOW-10);
    return c;
  }

  static User user(String email,String status){
    User u=new User("Jean","Dupont",email,"hash");
    try{
      Field id=User.class.getDeclaredField("id");id.setAccessible(true);id.set(u,UUID.randomUUID());
      Field st=User.class.getDeclaredField("status");st.setAccessible(true);st.set(u,status);
    }catch(ReflectiveOperationException e){throw new IllegalStateException(e);}
    return u;
  }

  AuthController controllerReturning(Map<String,Object> verifiedClaims){
    return new AuthController(users,encoder,jwt,db,PROJECT,null){
      @Override Map<String,Object> verifyFirebaseIdToken(String idToken){return verifiedClaims;}
    };
  }

  @Test
  void auth01_tokenMintedForAnotherFirebaseProjectIsRejected(){
    // aud and iss agree with each other, as in any genuine Google-signed
    // token, but name a project VEYRA does not own.
    ApiException ex=assertThrows(ApiException.class,
        ()->AuthController.validateFirebaseClaims(claims("attacker-project","uid-1"),PROJECT,NOW));
    assertEquals("FIREBASE_TOKEN_INVALID",ex.code());
    assertEquals(HttpStatus.UNAUTHORIZED,ex.status());
  }

  @Test
  void tokenForVeyraProjectPassesClaimValidation(){
    Map<String,Object> c=claims(PROJECT,"uid-1");
    c.put("firebase",Map.of("sign_in_provider","google.com"));
    AuthController.validateFirebaseClaims(c,PROJECT,NOW);
    assertEquals("google.com",c.get("provider"));
  }

  @Test
  void expiredTokenIsRejected(){
    Map<String,Object> c=claims(PROJECT,"uid-1");
    c.put("exp",NOW-1);
    assertThrows(ApiException.class,()->AuthController.validateFirebaseClaims(c,PROJECT,NOW));
  }

  @Test
  void missingProjectConfigurationFailsClosed(){
    ApiException ex=assertThrows(ApiException.class,
        ()->AuthController.validateFirebaseClaims(claims(PROJECT,"uid-1"),"",NOW));
    assertEquals("FIREBASE_NOT_CONFIGURED",ex.code());
  }

  @Test
  void auth02_unverifiedEmailNeverLinksToAnExistingAccount(){
    Map<String,Object> c=claims(PROJECT,"attacker-uid");
    c.put("email","victim@example.com");
    c.put("email_verified",false);
    when(db.queryForList(contains("firebase_uid=?"),eq(UUID.class),eq("attacker-uid"))).thenReturn(List.of());
    when(users.findByEmailIgnoreCase("victim@example.com")).thenReturn(Optional.of(user("victim@example.com","ACTIVE")));

    ApiException ex=assertThrows(ApiException.class,
        ()->controllerReturning(c).firebase(new AuthController.FirebaseLogin("t","CLIENT",null)));

    assertEquals("FIREBASE_EMAIL_NOT_VERIFIED",ex.code());
    verify(jwt,never()).issue(any(),any(),any());
  }

  @Test
  void verifiedEmailLinksAndBindsTheFirebaseUid(){
    Map<String,Object> c=claims(PROJECT,"uid-42");
    c.put("email","client@example.com");
    c.put("email_verified",true);
    User existing=user("client@example.com","ACTIVE");
    when(db.queryForList(contains("firebase_uid=?"),eq(UUID.class),eq("uid-42"))).thenReturn(List.of());
    when(users.findByEmailIgnoreCase("client@example.com")).thenReturn(Optional.of(existing));
    when(db.queryForList(contains("from roles"),eq(String.class),any(Object[].class))).thenReturn(List.of("CLIENT"));
    when(jwt.issue(any(),any(),any())).thenReturn("access");

    AuthController.Tokens t=controllerReturning(c).firebase(new AuthController.FirebaseLogin("t","CLIENT",null));

    assertEquals(existing.id(),t.userId());
    verify(db).update(contains("set firebase_uid=? where id=? and firebase_uid is null"),eq("uid-42"),eq(existing.id()));
  }

  @Test
  void phoneClaimFromNonPhoneProviderIsNotTrustedForLinking(){
    Map<String,Object> c=claims(PROJECT,"uid-7");
    c.put("phone_number","+33600000000");
    c.put("provider","google.com");
    when(db.queryForList(contains("firebase_uid=?"),eq(UUID.class),eq("uid-7"))).thenReturn(List.of());
    User created=user("firebase-uid-7@phone.veyra.local","ACTIVE");
    when(users.save(any(User.class))).thenReturn(created);
    when(db.queryForList(contains("from roles"),eq(String.class),any(Object[].class))).thenReturn(List.of("CLIENT"));
    when(jwt.issue(any(),any(),any())).thenReturn("access");

    controllerReturning(c).firebase(new AuthController.FirebaseLogin("t","CLIENT",null));

    verify(db,never()).queryForList(contains("where phone=?"),eq(UUID.class),any());
  }

  @Test
  void suspendedAccountCannotSignInThroughFirebase(){
    Map<String,Object> c=claims(PROJECT,"uid-9");
    User suspended=user("s@example.com","SUSPENDED");
    when(db.queryForList(contains("firebase_uid=?"),eq(UUID.class),eq("uid-9"))).thenReturn(List.of(suspended.id()));
    when(users.findById(suspended.id())).thenReturn(Optional.of(suspended));

    ApiException ex=assertThrows(ApiException.class,
        ()->controllerReturning(c).firebase(new AuthController.FirebaseLogin("t","CLIENT",null)));

    assertEquals("ACCOUNT_NOT_ACTIVE",ex.code());
    verify(jwt,never()).issue(any(),any(),any());
  }
}
