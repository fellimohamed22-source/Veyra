package com.veyra.auth;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.*;

/**
 * CL-AUTH-05 / DEC-07: the app verifies the phone number with Firebase
 * Phone Auth (SMS code) and sends the resulting ID token. Only a token
 * of VEYRA's Firebase project, signed in with the "phone" provider,
 * proves ownership of its phone_number claim.
 */
@RestController
@RequestMapping("/api/v1/me/phone")
public class PhoneVerificationController {
  private final JdbcTemplate db;
  private final String firebaseProjectId;

  public PhoneVerificationController(JdbcTemplate db,@Value("${veyra.firebase.project-id}") String firebaseProjectId){
    this.db=db;
    this.firebaseProjectId=firebaseProjectId;
  }

  public record Proof(@NotBlank String idToken){}

  Map<String,Object> verifyToken(String idToken){
    return FirebaseIdTokens.verify(idToken,firebaseProjectId);
  }

  @PostMapping("/verify")
  @Transactional
  public Map<String,Object> verify(@Valid @RequestBody Proof proof){
    Map<String,Object> claims=verifyToken(proof.idToken());
    String phone=Objects.toString(claims.get("phone_number"),"").trim();
    if(!"phone".equals(claims.get("provider"))||phone.isEmpty())
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"PHONE_PROOF_REQUIRED");
    UUID user=CurrentUser.id();
    Integer taken=db.queryForObject("select count(*) from users where phone=? and phone_verified_at is not null and id<>?",Integer.class,phone,user);
    if(taken!=null&&taken>0)throw new ApiException(HttpStatus.CONFLICT,"PHONE_ALREADY_USED");
    db.update("update users set phone=?,phone_verified_at=now(),updated_at=now() where id=?",phone,user);
    return Map.of("phone",phone,"verified",true);
  }

  @GetMapping
  public Map<String,Object> status(){
    List<Map<String,Object>> rows=db.queryForList("select phone,phone_verified_at from users where id=?",CurrentUser.id());
    if(rows.isEmpty())throw new ApiException(HttpStatus.NOT_FOUND,"NOT_FOUND");
    Map<String,Object> result=new LinkedHashMap<>();
    result.put("phone",rows.getFirst().get("phone"));
    result.put("verified",rows.getFirst().get("phone_verified_at")!=null);
    return result;
  }
}
