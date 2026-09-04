package com.veyra.provider;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.Message;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.io.FileInputStream;
import java.util.*;

@Component
@ConditionalOnProperty(name="veyra.firebase.enabled",havingValue="true")
public class FirebasePushProvider implements PushProvider {
  private final JdbcTemplate db;

  public FirebasePushProvider(
      JdbcTemplate db,
      @Value("${veyra.firebase.credentials-path:}") String credentialsPath) throws Exception {
    this.db=db;
    if(credentialsPath==null || credentialsPath.isBlank()) {
      throw new IllegalStateException("FIREBASE_CREDENTIALS_PATH_REQUIRED");
    }
    if(FirebaseApp.getApps().isEmpty()){
      try(FileInputStream in=new FileInputStream(credentialsPath)){
        FirebaseOptions options=FirebaseOptions.builder()
          .setCredentials(GoogleCredentials.fromStream(in))
          .build();
        FirebaseApp.initializeApp(options);
      }
    }
  }

  @Override
  public boolean send(UUID userId,String templateCode,Map<String,Object> data){
    List<String> tokens=db.queryForList(
      "select push_token from user_devices where user_id=? and active=true order by last_seen_at desc",
      String.class,userId);
    if(tokens.isEmpty()) return false;
    boolean success=false;
    for(String token:tokens){
      try{
        Message.Builder builder=Message.builder()
          .setToken(token)
          .putData("templateCode",templateCode);
        for(var entry:data.entrySet()){
          if(entry.getValue()!=null) builder.putData(entry.getKey(),String.valueOf(entry.getValue()));
        }
        FirebaseMessaging.getInstance().send(builder.build());
        success=true;
      }catch(Exception ignored){}
    }
    return success;
  }
}
