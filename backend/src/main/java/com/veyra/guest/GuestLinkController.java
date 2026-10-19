package com.veyra.guest;

import com.veyra.config.PlatformSettings;
import com.veyra.provider.SmsProvider;
import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import com.veyra.shared.DbTime;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.*;

/**
 * PART-13: the partner shares a tracking link with its passenger (no
 * account). PART-03: the public view is minimal, expires, can be revoked,
 * never exposes a phone number or a price, and answers the same 404 for
 * unknown, expired or revoked links.
 */
@RestController
@RequestMapping("/api/v1")
public class GuestLinkController {
  static final java.util.regex.Pattern TOKEN=java.util.regex.Pattern.compile("[A-Za-z0-9_-]{43}");
  private final JdbcTemplate db;
  private final SmsProvider sms;
  private final String baseUrl;
  private final PlatformSettings settings;
  private final SecureRandom random=new SecureRandom();

  public GuestLinkController(JdbcTemplate db,SmsProvider sms,@Value("${veyra.guest.base-url:}") String baseUrl){
    this.db=db;
    this.sms=sms;
    this.baseUrl=baseUrl==null?"":baseUrl.trim().replaceAll("/+$","");
    this.settings=new PlatformSettings(db);
  }

  public record LinkRequest(Boolean sendSms){}

  @PostMapping("/partner/{partnerId}/bookings/{bookingId}/guest-link")
  @Transactional
  public Map<String,Object> create(@PathVariable UUID partnerId,@PathVariable UUID bookingId,@RequestBody(required=false) LinkRequest req){
    Map<String,Object> b=partnerBooking(partnerId,bookingId);
    if(Set.of("CANCELLED","EXPIRED","COMPLETED","CLOSED").contains(b.get("status")))
      throw new ApiException(HttpStatus.CONFLICT,"BOOKING_NOT_SHAREABLE");
    // One active link per booking: a new link replaces the previous one.
    db.update("update guest_access_links set revoked_at=now() where booking_id=? and revoked_at is null",bookingId);
    byte[] raw=new byte[32];
    random.nextBytes(raw);
    String token=Base64.getUrlEncoder().withoutPadding().encodeToString(raw);
    OffsetDateTime pickup=DbTime.toOffsetDateTime(b.get("scheduled_at"));
    OffsetDateTime expires=pickup.plusHours(settings.get("guest.link_hours_after_pickup",24));
    db.update("insert into guest_access_links(booking_id,token_hash,expires_at,created_by) values (?,?,?,?)",bookingId,sha256(token),expires,CurrentUser.id());
    String url=(baseUrl.isEmpty()?"":baseUrl)+"/suivi/"+token;
    boolean smsSent=false;
    String phone=(String)b.get("beneficiary_phone_snapshot");
    if(req!=null&&Boolean.TRUE.equals(req.sendSms())){
      if(baseUrl.isEmpty())throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"GUEST_BASE_URL_NOT_CONFIGURED");
      if(phone==null||phone.isBlank())throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"BENEFICIARY_PHONE_REQUIRED");
      if(!sms.isConfigured())throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"SMS_NOT_CONFIGURED");
      String when=pickup.atZoneSameInstant(ZoneId.of("Europe/Paris")).format(DateTimeFormatter.ofPattern("dd/MM 'à' HH:mm"));
      String e164=toE164(phone);
      if(e164==null)throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"BENEFICIARY_PHONE_INVALID");
      smsSent=sms.send(e164,"VEYRA : suivez votre trajet du "+when+" : "+url);
    }
    Map<String,Object> result=new LinkedHashMap<>();
    result.put("url",url);
    result.put("expiresAt",expires);
    result.put("smsSent",smsSent);
    return result;
  }

  @DeleteMapping("/partner/{partnerId}/bookings/{bookingId}/guest-link")
  @Transactional
  public void revoke(@PathVariable UUID partnerId,@PathVariable UUID bookingId){
    partnerBooking(partnerId,bookingId);
    db.update("update guest_access_links set revoked_at=now() where booking_id=? and revoked_at is null",bookingId);
  }

  @GetMapping("/guest/bookings/{token}")
  public ResponseEntity<Map<String,Object>> view(@PathVariable String token){
    if(!TOKEN.matcher(token).matches())throw invalid();
    List<Map<String,Object>> rows=db.queryForList(
        "select sb.id,sb.status,sb.scheduled_at,sb.pickup_address,sb.dropoff_address,sb.beneficiary_name_snapshot,sb.payer_type,sb.payment_method," +
        "bfs.customer_total_amount_minor,bfs.currency,exists(select 1 from payments p where p.booking_id=sb.id and p.status='CAPTURED') as paid," +
        "u.first_name as driver_first_name,v.brand,v.model,v.color,v.plate_number " +
        "from guest_access_links g join scheduled_bookings sb on sb.id=g.booking_id " +
        "left join booking_financial_snapshots bfs on bfs.booking_id=sb.id " +
        "left join drivers d on d.id=sb.selected_driver_id left join users u on u.id=d.user_id " +
        "left join lateral (select v.* from vehicles v where v.driver_id=d.id and v.status='APPROVED' and v.category_id=sb.category_id order by v.id limit 1) v on true " +
        "where g.token_hash=? and g.revoked_at is null and g.expires_at>now()",sha256(token));
    if(rows.isEmpty())throw invalid();
    Map<String,Object> r=rows.getFirst();
    String status=(String)r.get("status");
    Map<String,Object> view=new LinkedHashMap<>();
    view.put("status",status);
    view.put("scheduledAt",r.get("scheduled_at"));
    view.put("pickupAddress",r.get("pickup_address"));
    view.put("dropoffAddress",r.get("dropoff_address"));
    view.put("passengerFirstName",firstName((String)r.get("beneficiary_name_snapshot")));
    // PART-10: the passenger pays through this link when the establishment chose so.
    if("GUEST".equals(r.get("payer_type"))&&"ONLINE".equals(r.get("payment_method"))&&r.get("customer_total_amount_minor")!=null){
      Map<String,Object> payment=new LinkedHashMap<>();
      payment.put("amountMinor",r.get("customer_total_amount_minor"));
      payment.put("currency",r.get("currency"));
      payment.put("paid",Boolean.TRUE.equals(r.get("paid")));
      payment.put("payable",Set.of("CONFIRMED","DRIVER_EN_ROUTE","DRIVER_ARRIVED").contains(status));
      view.put("payment",payment);
    }
    boolean assigned=Set.of("CONFIRMED","DRIVER_EN_ROUTE","DRIVER_ARRIVED","IN_PROGRESS","COMPLETED").contains(status);
    if(assigned&&r.get("driver_first_name")!=null){
      view.put("driverFirstName",r.get("driver_first_name"));
      view.put("vehicle",String.join(" ",Objects.toString(r.get("brand"),""),Objects.toString(r.get("model"),"")).trim());
      view.put("vehicleColor",r.get("color"));
      view.put("plate",r.get("plate_number"));
    }
    if(Set.of("DRIVER_EN_ROUTE","DRIVER_ARRIVED","IN_PROGRESS").contains(status)){
      List<Map<String,Object>> loc=db.queryForList(
          "select cdl.lat,cdl.lng,cdl.recorded_at from current_driver_locations cdl where cdl.booking_id=? and cdl.recorded_at>now()-interval '5 minutes'",
          r.get("id"));
      if(!loc.isEmpty())view.put("driverLocation",loc.getFirst());
    }
    return ResponseEntity.ok().header("X-Robots-Tag","noindex, nofollow").header("Cache-Control","no-store").body(view);
  }

  private Map<String,Object> partnerBooking(UUID partnerId,UUID bookingId){
    Integer member=db.queryForObject("select count(*) from partner_users where partner_id=? and user_id=? and status='ACTIVE'",Integer.class,partnerId,CurrentUser.id());
    if(member==null||member==0)throw new ApiException(HttpStatus.FORBIDDEN,"PARTNER_SCOPE_FORBIDDEN");
    List<Map<String,Object>> rows=db.queryForList("select status,scheduled_at,beneficiary_phone_snapshot from scheduled_bookings where id=? and partner_id=?",bookingId,partnerId);
    if(rows.isEmpty())throw new ApiException(HttpStatus.NOT_FOUND,"NOT_FOUND");
    return rows.getFirst();
  }

  /** French numbers typed as 06... become +336... (service in France first, DEC-06). */
  static String toE164(String input){
    String d=input.replaceAll("[\\s.()-]","");
    if(d.matches("\\+[1-9]\\d{6,14}"))return d;
    if(d.matches("0[1-9]\\d{8}"))return "+33"+d.substring(1);
    return null;
  }

  static String firstName(String full){
    if(full==null||full.isBlank())return null;
    return full.trim().split("\\s+")[0];
  }

  private static ApiException invalid(){
    return new ApiException(HttpStatus.NOT_FOUND,"GUEST_LINK_INVALID");
  }

  static String sha256(String value){
    try{
      return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
    }catch(Exception e){throw new IllegalStateException(e);}
  }
}
