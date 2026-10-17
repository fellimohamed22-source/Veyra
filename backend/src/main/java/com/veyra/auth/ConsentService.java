package com.veyra.auth;

import com.veyra.shared.ApiException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.*;

/**
 * Consent journal (V040). Terms and privacy are mandatory to create an
 * account; marketing is optional, distinct and never pre-granted.
 */
@Service
public class ConsentService {
  public static final Set<String> TYPES=Set.of("TERMS","PRIVACY","MARKETING");

  private final JdbcTemplate db;
  private final Map<String,String> versions;

  public ConsentService(
      JdbcTemplate db,
      @Value("${veyra.legal.terms-version}") String termsVersion,
      @Value("${veyra.legal.privacy-version}") String privacyVersion,
      @Value("${veyra.legal.marketing-version}") String marketingVersion){
    this.db=db;
    this.versions=Map.of("TERMS",termsVersion,"PRIVACY",privacyVersion,"MARKETING",marketingVersion);
  }

  /** Rejects a signup that did not explicitly accept both mandatory documents. */
  public static void requireMandatory(Boolean acceptTerms,Boolean acceptPrivacy){
    if(!Boolean.TRUE.equals(acceptTerms)||!Boolean.TRUE.equals(acceptPrivacy))
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"CONSENT_REQUIRED");
  }

  public void recordSignup(UUID userId,boolean marketingOptIn,String source){
    record(userId,"TERMS",true,source);
    record(userId,"PRIVACY",true,source);
    record(userId,"MARKETING",marketingOptIn,source);
  }

  public void record(UUID userId,String type,boolean granted,String source){
    if(!TYPES.contains(type))throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_CONSENT_TYPE");
    db.update("insert into user_consents(user_id,consent_type,granted,document_version,source) values (?,?,?,?,?)",
        userId,type,granted,versions.get(type),source);
  }

  /** Latest decision per type, plus the version currently in force. */
  public Map<String,Object> current(UUID userId){
    Map<String,Object> result=new LinkedHashMap<>();
    for(String type:List.of("TERMS","PRIVACY","MARKETING")){
      List<Map<String,Object>> rows=db.queryForList(
          "select granted,document_version,created_at from user_consents where user_id=? and consent_type=? order by created_at desc limit 1",
          userId,type);
      Map<String,Object> entry=new LinkedHashMap<>();
      entry.put("granted",!rows.isEmpty()&&Boolean.TRUE.equals(rows.getFirst().get("granted")));
      entry.put("acceptedVersion",rows.isEmpty()?null:rows.getFirst().get("document_version"));
      entry.put("currentVersion",versions.get(type));
      entry.put("decidedAt",rows.isEmpty()?null:rows.getFirst().get("created_at"));
      result.put(type,entry);
    }
    return result;
  }
}
