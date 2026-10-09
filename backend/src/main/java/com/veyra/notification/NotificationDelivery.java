package com.veyra.notification;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import java.util.*;
@Component
public class NotificationDelivery {
  private final JdbcTemplate db;
  public NotificationDelivery(JdbcTemplate db){this.db=db;}

  // Bug réel : ce job marquait SENT *toutes* les notifications PENDING, tous
  // canaux confondus, sans rien envoyer. NotificationDispatcher (qui, lui, envoie
  // réellement via FCM) ne traite que channel='PUSH' et tourne à la même cadence
  // de 3 s : dès que ce job passait en premier, les notifications push étaient
  // marquées SENT sans jamais partir, et le dispatcher ne trouvait plus rien --
  // d'où l'absence totale de NOTIFICATION_DISPATCH_RUN malgré Firebase initialisé.
  // Seul le canal PUSH est inséré aujourd'hui (OutboxPublisher), ce job ne doit donc
  // toucher que les canaux qui n'ont pas de livraison dédiée.
  @Scheduled(fixedDelayString = "${veyra.notifications.poll-ms:3000}")
  public void deliverInApp(){
    var rows=db.queryForList("select id from notifications where status='PENDING' and channel<>'PUSH' order by created_at asc limit 100");
    for(var row:rows){
      db.update("update notifications set status='SENT',sent_at=now() where id=? and status='PENDING' and channel<>'PUSH'",row.get("id"));
    }
  }
}
