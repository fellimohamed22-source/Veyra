package com.veyra.auth;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;

import java.nio.charset.StandardCharsets;
import java.util.*;

/**
 * Verification of Firebase ID tokens, shared by social sign-in and phone
 * verification: RS256 signature against Google's published certificates,
 * then claims bound to VEYRA's own Firebase project.
 */
public final class FirebaseIdTokens {
  private static final ObjectMapper JSON=new ObjectMapper();

  private FirebaseIdTokens(){}

  @SuppressWarnings("unchecked")
  public static Map<String,Object> verify(String idToken,String expectedProjectId){
    try{
      String[] parts=idToken.split("\\.");
      if(parts.length!=3)throw new ApiException(HttpStatus.UNAUTHORIZED,"FIREBASE_TOKEN_INVALID");
      Map<String,Object> header=JSON.readValue(Base64.getUrlDecoder().decode(parts[0]),Map.class);
      if(!"RS256".equals(header.get("alg")))throw new ApiException(HttpStatus.UNAUTHORIZED,"FIREBASE_TOKEN_INVALID");
      String kid=Objects.toString(header.get("kid"),"");
      if(kid.isEmpty())throw new ApiException(HttpStatus.UNAUTHORIZED,"FIREBASE_TOKEN_INVALID");
      java.net.http.HttpClient http=java.net.http.HttpClient.newBuilder().connectTimeout(java.time.Duration.ofSeconds(5)).build();
      var req=java.net.http.HttpRequest.newBuilder(java.net.URI.create("https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"))
          .timeout(java.time.Duration.ofSeconds(8)).GET().build();
      var resp=http.send(req,java.net.http.HttpResponse.BodyHandlers.ofString());
      if(resp.statusCode()!=200)throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"FIREBASE_KEYS_UNAVAILABLE");
      Map<String,String> certs=JSON.readValue(resp.body(),Map.class);
      String pem=certs.get(kid);
      if(pem==null)throw new ApiException(HttpStatus.UNAUTHORIZED,"FIREBASE_TOKEN_INVALID");
      String clean=pem.replace("-----BEGIN CERTIFICATE-----","").replace("-----END CERTIFICATE-----","").replaceAll("\\s","");
      var cert=(java.security.cert.X509Certificate)java.security.cert.CertificateFactory.getInstance("X.509")
          .generateCertificate(new java.io.ByteArrayInputStream(Base64.getDecoder().decode(clean)));
      java.security.Signature signature=java.security.Signature.getInstance("SHA256withRSA");
      signature.initVerify(cert.getPublicKey());
      signature.update((parts[0]+"."+parts[1]).getBytes(StandardCharsets.UTF_8));
      if(!signature.verify(Base64.getUrlDecoder().decode(parts[2])))throw new ApiException(HttpStatus.UNAUTHORIZED,"FIREBASE_TOKEN_INVALID");
      Map<String,Object> claims=JSON.readValue(Base64.getUrlDecoder().decode(parts[1]),Map.class);
      validateClaims(claims,expectedProjectId,System.currentTimeMillis()/1000L);
      return claims;
    }catch(ApiException e){throw e;}
    catch(Exception e){throw new ApiException(HttpStatus.UNAUTHORIZED,"FIREBASE_TOKEN_INVALID");}
  }

  /**
   * The token must have been minted for VEYRA's own Firebase project: a
   * Google-signed token from any other project is equally well signed,
   * so comparing aud with iss alone accepted tokens from projects an
   * attacker controls.
   */
  public static void validateClaims(Map<String,Object> claims,String expectedProjectId,long nowEpochSeconds){
    if(expectedProjectId==null||expectedProjectId.isBlank())throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"FIREBASE_NOT_CONFIGURED");
    long exp=((Number)claims.getOrDefault("exp",0)).longValue();
    long iat=((Number)claims.getOrDefault("iat",0)).longValue();
    String aud=Objects.toString(claims.get("aud"),"");
    String iss=Objects.toString(claims.get("iss"),"");
    String sub=Objects.toString(claims.get("sub"),"");
    if(!expectedProjectId.equals(aud)
        ||!("https://securetoken.google.com/"+expectedProjectId).equals(iss)
        ||sub.isEmpty()||sub.length()>128
        ||exp<=nowEpochSeconds||iat>nowEpochSeconds+60)
      throw new ApiException(HttpStatus.UNAUTHORIZED,"FIREBASE_TOKEN_INVALID");
    Object firebase=claims.get("firebase");
    if(firebase instanceof Map<?,?> fm)claims.put("provider",Objects.toString(fm.get("sign_in_provider"),"firebase"));
  }
}
