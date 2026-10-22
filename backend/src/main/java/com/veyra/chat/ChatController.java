package com.veyra.chat;
import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.web.bind.annotation.*;
import java.util.*;
@RestController @RequestMapping("/api/v1/bookings/{bookingId}/chat")public class ChatController{
    private final JdbcTemplate db;
    private final SimpMessagingTemplate ws;
    public ChatController(JdbcTemplate d,SimpMessagingTemplate w){
        db=d;
        ws=w;
    }
    public record Msg(String body){
    }
    @PostMapping("/messages")ResponseEntity<Map<String,Object>>send(@PathVariable UUID bookingId,@RequestBody Msg m){
        participant(bookingId);
        if(m.body()==null||m.body().isBlank()||m.body().length()>2000)throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"INVALID_MESSAGE");
        if(!staff()&&!Boolean.TRUE.equals(db.queryForObject("select "+WINDOW_OPEN_SQL+" from scheduled_bookings sb where sb.id=?",Boolean.class,bookingId)))
            throw new ApiException(HttpStatus.FORBIDDEN,"CHAT_WINDOW_CLOSED");
        UUID c=conversation(bookingId),id=UUID.randomUUID(),u=CurrentUser.id();
        java.time.OffsetDateTime sentAt=db.queryForObject("insert into chat_messages(id,conversation_id,sender_user_id,body) values (?,?,?,?) returning sent_at",java.time.OffsetDateTime.class,id,c,u,m.body());
        // sentAt lets the apps place the message last (newest at the bottom).
        Map<String,Object>x=Map.of("id",id,"senderUserId",u,"body",m.body(),"sentAt",sentAt==null?java.time.OffsetDateTime.now().toString():sentAt.toString());
        ws.convertAndSend("/topic/bookings/"+bookingId+"/chat",x);
        return ResponseEntity.status(201).body(x);
    }
    @GetMapping("/messages")List<Map<String,Object>>list(@PathVariable UUID bookingId){
        participant(bookingId);
        return db.queryForList("select cm.id,cm.sender_user_id,cm.body,cm.status,cm.sent_at,cm.read_at from chat_messages cm join chat_conversations c on c.id=cm.conversation_id where c.booking_id=? order by cm.sent_at",bookingId);
    }
    /**
     * CL-15: customer and driver may exchange messages from 30 minutes
     * before pickup until 1 hour after the ride ends. History stays
     * readable; only sending is gated. Admin/support are not subject to
     * the window (incident handling). Ride end = COMPLETED transition in
     * booking_status_history, falling back to updated_at for rows that
     * predate history recording.
     */
    static final String RIDE_END_SQL="coalesce((select max(h.created_at) from booking_status_history h where h.booking_id=sb.id and h.to_status='COMPLETED'),sb.updated_at)";
    static final String WINDOW_OPEN_SQL="(now()>=sb.scheduled_at-interval '30 minutes' and (sb.status not in ('COMPLETED','CLOSED') or now()<="+RIDE_END_SQL+"+interval '1 hour'))";
    @GetMapping("/availability")Map<String,Object>availability(@PathVariable UUID bookingId){
        participant(bookingId);
        Map<String,Object>w=db.queryForMap("select "+WINDOW_OPEN_SQL+" as open,sb.scheduled_at-interval '30 minutes' as opens_at,case when sb.status in ('COMPLETED','CLOSED') then "+RIDE_END_SQL+"+interval '1 hour' end as closes_at from scheduled_bookings sb where sb.id=?",bookingId);
        Map<String,Object>x=new LinkedHashMap<>();
        x.put("open",staff()||Boolean.TRUE.equals(w.get("open")));
        x.put("opensAt",w.get("opens_at"));
        x.put("closesAt",w.get("closes_at"));
        return x;
    }
    private static boolean staff(){
        return CurrentUser.hasRole("ADMIN")||CurrentUser.hasRole("SUPPORT");
    }
    private UUID conversation(UUID b){
        List<UUID>x=db.queryForList("select id from chat_conversations where booking_id=?",UUID.class,b);
        if(!x.isEmpty())return x.getFirst();
        UUID id=UUID.randomUUID();
        db.update("insert into chat_conversations(id,booking_id) values (?,?)",id,b);
        return id;
    }
    private void participant(UUID b){
        if(CurrentUser.hasRole("ADMIN")||CurrentUser.hasRole("SUPPORT"))return;
        UUID u=CurrentUser.id();
        Integer n=db.queryForObject("select count(*) from scheduled_bookings sb left join drivers d on d.id=sb.selected_driver_id left join partner_users pu on pu.partner_id=sb.partner_id and pu.user_id=? where sb.id=? and sb.status in ('CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS','COMPLETED','CLOSED') and (sb.creator_user_id=? or d.user_id=? or pu.id is not null)",Integer.class,u,b,u,u);
        if(n==0)throw new ApiException(HttpStatus.FORBIDDEN,"CHAT_NOT_ALLOWED");
    }
}
