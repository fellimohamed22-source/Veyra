package com.veyra.provider;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.Notification;
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

  private String title(String code){
    return switch(code){
      case "NEW_BOOKING" -> "Nouvelle demande Veyra";
      case "NEW_OFFER" -> "Nouvelle offre chauffeur";
      case "OFFER_ACCEPTED" -> "Votre offre a été choisie";
      case "DRIVER_BOOKING_REMINDER" -> "Rappel course Veyra";
      case "CUSTOMER_BOOKING_REMINDER" -> "Rappel réservation Veyra";
      case "PIN_AVAILABLE" -> "Votre PIN Veyra est disponible";
      default -> "Veyra";
    };
  }

  private String body(String code){
    return switch(code){
      case "NEW_BOOKING" -> "Une nouvelle réservation programmée est disponible.";
      case "NEW_OFFER" -> "Un chauffeur vient de proposer un prix.";
      case "OFFER_ACCEPTED" -> "Une réservation vous a été attribuée.";
      case "DRIVER_BOOKING_REMINDER" -> "Votre prochaine course programmée approche.";
      case "CUSTOMER_BOOKING_REMINDER" -> "Votre réservation programmée approche.";
      case "PIN_AVAILABLE" -> "Le PIN 4 chiffres de démarrage est maintenant disponible.";
      default -> "Une réservation Veyra a été mise à jour.";
    };
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
          .setNotification(Notification.builder()
            .setTitle(title(templateCode))
            .setBody(body(templateCode))
            .build())
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
