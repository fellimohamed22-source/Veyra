package com.veyra.booking;
import com.veyra.booking.BookingDtos.*;
import com.veyra.security.CurrentUser;
import jakarta.validation.constraints.Pattern;
import com.veyra.shared.ApiException;
import com.veyra.shared.DbTime;
import jakarta.validation.Valid;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.*;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.math.*;
import java.security.SecureRandom;
import java.time.*;
import java.util.*;
@RestController @RequestMapping("/api/v1") public class BookingController{
    private final JdbcTemplate db;
    private final PasswordEncoder enc;
    private final com.veyra.security.PinCrypto pinCrypto;
    private final com.veyra.finance.LedgerService ledger;
    private final SecureRandom rnd=new SecureRandom();
    private final long minLead,maxWindow,normalClose,shortClose;
    public BookingController(JdbcTemplate d,PasswordEncoder e,com.veyra.security.PinCrypto pc,com.veyra.finance.LedgerService l,@Value("${veyra.marketplace.min-lead-minutes}")long a,@Value("${veyra.marketplace.max-offer-window-hours}")long b,@Value("${veyra.marketplace.normal-close-before-minutes}")long c,@Value("${veyra.marketplace.short-close-before-minutes}")long f){
        db=d;
        enc=e;
        pinCrypto=pc;
        ledger=l;
        minLead=a;
        maxWindow=b;
        normalClose=c;
        shortClose=f;
    }
    @PostMapping("/scheduled-bookings") @Transactional ResponseEntity<Map<String,Object>> create(@Valid@RequestBody Create r){
        UUID u=CurrentUser.id();
        long mins=Duration.between(OffsetDateTime.now(),r.scheduledAt()).toMinutes();
        if(mins<minLead)throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"LEAD_TIME_TOO_SHORT");
        Integer activeZones=db.queryForObject("select count(*) from service_zone_versions where status='ACTIVE' and effective_from<=now() and (effective_to is null or effective_to>now())",Integer.class);
        if(activeZones!=null&&activeZones>0){
            Integer covered=db.queryForObject("select count(*) from service_zone_versions where status='ACTIVE' and effective_from<=now() and (effective_to is null or effective_to>now()) and ST_Covers(polygon::geometry,ST_SetSRID(ST_MakePoint(?,?),4326))",Integer.class,r.pickup().lng(),r.pickup().lat());
            if(covered==null||covered==0)throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"PICKUP_OUTSIDE_SERVICE_ZONE");
        }
        if(r.partnerId()!=null)member(r.partnerId(),u);
        if("PARTNER_INVOICE".equals(r.paymentMethod()))invoiceEligible(r.partnerId());
        OffsetDateTime now=OffsetDateTime.now(),close=mins>=240?min(r.scheduledAt().minusMinutes(normalClose),now.plusHours(maxWindow)):r.scheduledAt().minusMinutes(shortClose);
        UUID id=UUID.randomUUID();
        int passengerCount=r.passengerCount()==null?1:r.passengerCount();
        int baggageCount=r.baggageCount()==null?0:r.baggageCount();
        String offerVisibilityMode=db.queryForObject("select mode from offer_visibility_policy_versions where status='ACTIVE' order by version_no desc limit 1",String.class);
        db.update("insert into scheduled_bookings(id,creator_type,creator_user_id,partner_id,beneficiary_name_snapshot,beneficiary_phone_snapshot,pickup,pickup_address,dropoff,dropoff_address,scheduled_at,category_id,payment_method,payer_type,passenger_count,baggage_count,customer_notes,status,offer_window_ends_at,offer_visibility_mode) values (?,?,?,?,?,?,ST_SetSRID(ST_MakePoint(?,?),4326)::geography,?,ST_SetSRID(ST_MakePoint(?,?),4326)::geography,?,?,?,?,?,?,?,?,'OPEN_FOR_OFFERS',?,?)",id,r.partnerId()==null?"CLIENT":"PARTNER",u,r.partnerId(),r.beneficiaryName(),r.beneficiaryPhone(),r.pickup().lng(),r.pickup().lat(),r.pickup().address(),r.dropoff().lng(),r.dropoff().lat(),r.dropoff().address(),r.scheduledAt(),r.categoryId(),r.paymentMethod(),r.payerType(),passengerCount,baggageCount,r.customerNotes(),close,offerVisibilityMode);
        event(id,"booking.published");
            return ResponseEntity.status(201).body(Map.of("id",
            id,
            "status",
            "OPEN_FOR_OFFERS",
            "offerWindowEndsAt",
        close));
    }
    @GetMapping("/scheduled-bookings") List<Map<String,Object>> mine(){
        return db.queryForList("select id,creator_type,pickup_address,dropoff_address,scheduled_at,status,payment_method,selected_driver_id from scheduled_bookings where creator_user_id=? order by scheduled_at desc",CurrentUser.id());
    }
    @GetMapping("/driver/opportunities") List<Map<String,Object>> opportunities(    @RequestParam(defaultValue="date")String sort,    @RequestParam(required=false)UUID categoryId,    @RequestParam(required=false)OffsetDateTime from,    @RequestParam(required=false)OffsetDateTime to,    @RequestParam(required=false)Integer minPassengers,    @RequestParam(required=false)String pickupQuery,    @RequestParam(required=false)String destinationQuery){
        UUID d=driver();
        eligible(d);
        String order=switch(sort){
            case "date"->"scheduled_at asc";
            case "newest"->"created_at desc";
            case "pickup"->"pickup_address asc, scheduled_at asc";
            case "destination"->"dropoff_address asc, scheduled_at asc";
            case "passengers"->"passenger_count desc, scheduled_at asc";
            case "baggage"->"baggage_count desc, scheduled_at asc";
            default->"scheduled_at asc";
        }
        ;
        StringBuilder sql=new StringBuilder("select id,pickup_address,dropoff_address,scheduled_at,category_id,passenger_count,baggage_count,status,offer_window_ends_at from scheduled_bookings where status in ('OPEN_FOR_OFFERS','OFFERS_RECEIVED') and offer_window_ends_at>now()");
        List<Object> params=new ArrayList<>();
        if(categoryId!=null){
            sql.append(" and category_id=?");
            params.add(categoryId);
        }
        if(from!=null){
            sql.append(" and scheduled_at>=?");
            params.add(from);
        }
        if(to!=null){
            sql.append(" and scheduled_at<=?");
            params.add(to);
        }
        if(minPassengers!=null){
            sql.append(" and passenger_count>=?");
                params.add(Math.max(1,
                Math.min(minPassengers,
            9)));
        }
        if(pickupQuery!=null&&!pickupQuery.isBlank()){
            sql.append(" and pickup_address ilike ?");
            params.add("%"+pickupQuery.trim()+"%");
        }
        if(destinationQuery!=null&&!destinationQuery.isBlank()){
            sql.append(" and dropoff_address ilike ?");
            params.add("%"+destinationQuery.trim()+"%");
        }
        sql.append(" order by ").append(order).append(" limit 100");
        return db.queryForList(sql.toString(),params.toArray());
    }
    @PostMapping("/driver/opportunities/{bookingId}/offers") @Transactional ResponseEntity<Map<String,Object>> offer(@PathVariable UUID bookingId,@Valid@RequestBody Offer r){
        UUID d=driver();
        eligible(d);
        Map<String,Object>b=one("select status,offer_window_ends_at,scheduled_at from scheduled_bookings where id=? for update",bookingId);
            if(!Set.of("OPEN_FOR_OFFERS",
        "OFFERS_RECEIVED").contains(b.get("status"))||DbTime.toOffsetDateTime(b.get("offer_window_ends_at")).isBefore(OffsetDateTime.now()))throw new ApiException(HttpStatus.GONE,"OFFERS_CLOSED");
        Integer exists=db.queryForObject("select count(*) from driver_offers where booking_id=? and driver_id=? and status='ACTIVE'",Integer.class,bookingId,d);
        if(exists>0)throw new ApiException(HttpStatus.CONFLICT,"ACTIVE_OFFER_EXISTS");
        conflict(d,DbTime.toOffsetDateTime(b.get("scheduled_at")));
        String method=db.queryForObject("select payment_method from scheduled_bookings where id=?",String.class,bookingId);
        if("CASH".equals(method)){
            Long debt=db.queryForObject("select coalesce(sum(amount_minor-paid_amount_minor),0) from driver_platform_debts where driver_id=? and status in ('DUE','PARTIALLY_PAID','OVERDUE')",Long.class,d);
            if(debt!=null&&debt>=15000)throw new ApiException(HttpStatus.FORBIDDEN,"CASH_DEBT_LIMIT_REACHED");
            if(debt!=null&&debt>=10000){
                Integer activeCashOffers=db.queryForObject("select count(*) from driver_offers o join scheduled_bookings sb on sb.id=o.booking_id where o.driver_id=? and o.status='ACTIVE' and sb.payment_method='CASH'",Integer.class,d);
                if(activeCashOffers!=null&&activeCashOffers>=1)throw new ApiException(HttpStatus.FORBIDDEN,"CASH_DEBT_RESTRICTED");
            }
        }
        UUID id=UUID.randomUUID();
        db.update("insert into driver_offers(id,booking_id,driver_id,proposed_amount_minor,currency,status,expires_at) values (?,?,?,?,?,'ACTIVE',?)",id,bookingId,d,r.amountMinor(),r.currency(),b.get("offer_window_ends_at"));
        db.update("update scheduled_bookings set status='OFFERS_RECEIVED',updated_at=now() where id=? and status='OPEN_FOR_OFFERS'",bookingId);
        event(bookingId,"offer.created");
        Map<String,Object>response=new HashMap<>(Map.of("offerId",id));
        String visibilityMode=db.queryForObject("select offer_visibility_mode from scheduled_bookings where id=?",String.class,bookingId);
        if("BEST_VISIBLE".equals(visibilityMode)){
            // Business rule: the driver may only see the current lowest
            // price among the OTHER drivers' active offers -- never their
            // identity, and this must never block submission, only inform.
            Long bestOthers=db.queryForObject("select min(proposed_amount_minor) from driver_offers where booking_id=? and status='ACTIVE' and driver_id<>?",Long.class,bookingId,d);
            response.put("currentBestOtherOfferMinor",bestOthers);
            if(bestOthers!=null)response.put("differenceFromBestMinor",r.amountMinor()-bestOthers);
        }
        return ResponseEntity.status(201).body(response);
    }
    @GetMapping("/scheduled-bookings/{bookingId}/offers") List<Map<String,Object>> ownerOffers(@PathVariable UUID bookingId){
        Map<String,Object>b=one("select creator_user_id,partner_id from scheduled_bookings where id=?",bookingId);
        owner(b);
        int rate=rate((UUID)b.get("partner_id"));
            return db.query("select o.id,o.driver_id,o.proposed_amount_minor,o.currency,o.status,d.rating,u.first_name,u.last_name,v.brand,v.model,v.year,v.color,vc.display_name as vehicle_category from driver_offers o join drivers d on d.id=o.driver_id join users u on u.id=d.user_id left join vehicles v on v.driver_id=d.id and v.status='APPROVED' left join vehicle_categories vc on vc.id=v.category_id where o.booking_id=? and o.status='ACTIVE' order by o.proposed_amount_minor",(rs,
            n)->{
                long p=rs.getLong("proposed_amount_minor"),commissionAmount=commission(p,
                rate);
                Map<String,Object>result=new LinkedHashMap<>();
                result.put("offerId",
                rs.getObject("id",
                UUID.class));
                result.put("driverId",
                rs.getObject("driver_id",
                UUID.class));
                result.put("driverPriceMinor",
                p);
                result.put("commissionMinor",
                commissionAmount);
                result.put("totalMinor",
                p+commissionAmount);
                result.put("currency",
                rs.getString("currency"));
                result.put("rating",
                rs.getObject("rating")==null?0:rs.getBigDecimal("rating"));
                result.put("driverFirstName",
                rs.getString("first_name"));
                result.put("driverLastName",
                rs.getString("last_name"));
                result.put("vehicleBrand",
                rs.getString("brand"));
                result.put("vehicleModel",
                rs.getString("model"));
                result.put("vehicleYear",
                rs.getObject("year"));
                result.put("vehicleColor",
                rs.getString("color"));
                result.put("vehicleCategory",
                rs.getString("vehicle_category"));
                return result;
            }
        ,bookingId);
    }
    @PostMapping("/scheduled-bookings/{bookingId}/offers/{offerId}/accept") @Transactional Map<String,Object> accept(@PathVariable UUID bookingId,@PathVariable UUID offerId){
        Map<String,Object>b=one("select creator_user_id,partner_id,status,scheduled_at,payment_method from scheduled_bookings where id=? for update",bookingId);
        owner(b);
            if(!Set.of("OPEN_FOR_OFFERS",
        "OFFERS_RECEIVED").contains(b.get("status")))throw new ApiException(HttpStatus.CONFLICT,"BOOKING_CLOSED");
        Map<String,Object>o=one("select driver_id,proposed_amount_minor,currency,status from driver_offers where id=? and booking_id=? for update",offerId,bookingId);
        if(!"ACTIVE".equals(o.get("status")))throw new ApiException(HttpStatus.GONE,"OFFER_CLOSED");
        UUID d=(UUID)o.get("driver_id");
        conflict(d,DbTime.toOffsetDateTime(b.get("scheduled_at")));
        int rate=rate((UUID)b.get("partner_id"));
        long p=((Number)o.get("proposed_amount_minor")).longValue(),c=commission(p,rate),total=p+c;
        if("PARTNER_INVOICE".equals(b.get("payment_method"))){
            UUID partnerId=(UUID)b.get("partner_id");
            Map<String,Object>credit=one("select po.credit_limit_minor,coalesce(pia.outstanding_minor,0) outstanding_minor,po.credit_status,pia.status from partner_organizations po join partner_invoice_accounts pia on pia.partner_id=po.id where po.id=? for update",partnerId);
            long limit=((Number)credit.get("credit_limit_minor")).longValue(),outstanding=((Number)credit.get("outstanding_minor")).longValue();
                if(!"APPROVED".equals(credit.get("credit_status"))||!"ACTIVE".equals(credit.get("status"))||Math.addExact(outstanding,
            total)>limit)throw new ApiException(HttpStatus.PAYMENT_REQUIRED,"PARTNER_CREDIT_LIMIT_EXCEEDED");
        }
        String pin=String.format("%04d",rnd.nextInt(10000));
        db.update("update driver_offers set status=case when id=? then 'ACCEPTED' else 'REJECTED_BY_SELECTION' end where booking_id=? and status='ACTIVE'",offerId,bookingId);
        db.update("update scheduled_bookings set selected_offer_id=?,selected_driver_id=?,pin_hash=?,pin_encrypted=?,status='CONFIRMED',updated_at=now() where id=?",offerId,d,enc.encode(pin),pinCrypto.encrypt(pin),bookingId);
        UUID policy=db.queryForObject("select id from commission_policy_versions where status='ACTIVE' and ((?::uuid is not null and scope_type='PARTNER' and partner_id=?) or scope_type='STANDARD') order by case when scope_type='PARTNER' then 0 else 1 end,version_no desc limit 1",UUID.class,b.get("partner_id"),b.get("partner_id"));
        db.update("insert into booking_financial_snapshots values (?,?,?,?,?,?,?,?,?,?)",bookingId,offerId,policy,rate,p,c,total,p,o.get("currency"),b.get("payment_method"));
        event(bookingId,"booking.confirmed");
        return Map.of("bookingId",bookingId,"status","CONFIRMED","driverId",d,"driverNetMinor",p,"commissionMinor",c,"totalMinor",total,"currency",o.get("currency"));
    }
    @PostMapping("/bookings/{id}/en-route") void enroute(@PathVariable UUID id){
        driverTransition(id,"CONFIRMED","DRIVER_EN_ROUTE",null);
    }
    @PostMapping("/bookings/{id}/arrived") void arrived(@PathVariable UUID id){
        driverTransition(id,"DRIVER_EN_ROUTE","DRIVER_ARRIVED",null);
    }
    public record Pin(@Pattern(regexp="\\d{4}")String pin){
    }
    @PostMapping("/bookings/{id}/start") void start(@PathVariable UUID id,@Valid@RequestBody Pin p){
        driverTransition(id,"DRIVER_ARRIVED","IN_PROGRESS",p.pin());
    }
    @PostMapping("/bookings/{id}/complete") @Transactional void complete(@PathVariable UUID id){
        driverTransition(id,"IN_PROGRESS","COMPLETED",null);
        Map<String,Object>x=one("select sb.payment_method,sb.selected_driver_id,bfs.platform_commission_amount_minor,bfs.driver_net_amount_minor,bfs.customer_total_amount_minor,bfs.currency from scheduled_bookings sb join booking_financial_snapshots bfs on bfs.booking_id=sb.id where sb.id=?",id);
        String method=(String)x.get("payment_method");
        long commission=((Number)x.get("platform_commission_amount_minor")).longValue();
        long driverNet=((Number)x.get("driver_net_amount_minor")).longValue();
        long total=((Number)x.get("customer_total_amount_minor")).longValue();
        String currency=(String)x.get("currency");
        if("CASH".equals(method)){
            db.update("insert into driver_platform_debts(driver_id,booking_id,amount_minor,currency) values (?,?,?,?) on conflict(booking_id) do nothing",x.get("selected_driver_id"),id,commission,currency);
            // Driver already holds the customer's cash directly -- only the
            // platform's commission is a receivable here, no DRIVER_PAYABLE
            // entry (there's nothing further platform owes the driver).
            ledger.post("BOOKING_COMPLETED_CASH",id,"Commission due from driver (cash booking)",currency,List.of(
                com.veyra.finance.LedgerService.Entry.debit("DRIVER_PLATFORM_DEBT",commission),
                com.veyra.finance.LedgerService.Entry.credit("PLATFORM_REVENUE",commission)));
        }else{
            db.update("insert into driver_payables(driver_id,booking_id,amount_minor,currency) values (?,?,?,?) on conflict(booking_id) do nothing",x.get("selected_driver_id"),id,driverNet,currency);
            // ONLINE: funds already captured via the PSP (payments table),
            // recognized here as cleared. PARTNER_INVOICE: no payment was
            // ever captured -- the partner owes the total instead, a real
            // receivable rather than PSP-held cash.
            String debitAccount="PARTNER_INVOICE".equals(method)?"PARTNER_RECEIVABLE":"PAYMENT_PROCESSOR_CLEARING";
            ledger.post("BOOKING_COMPLETED_"+method,id,"Commission and driver payable recognized",currency,List.of(
                com.veyra.finance.LedgerService.Entry.debit(debitAccount,total),
                com.veyra.finance.LedgerService.Entry.credit("PLATFORM_REVENUE",commission),
                com.veyra.finance.LedgerService.Entry.credit("DRIVER_PAYABLE",driverNet)));
        }
    }
    @Transactional void driverTransition(UUID id,String from,String to,String pin){
        UUID d=driver();
        Map<String,Object>b=one("select selected_driver_id,status,pin_hash,pin_failed_attempts,pin_locked_until from scheduled_bookings where id=? for update",id);
        if(!d.equals(b.get("selected_driver_id")))throw new ApiException(HttpStatus.FORBIDDEN,"NOT_SELECTED_DRIVER");
        if(!from.equals(b.get("status")))throw new ApiException(HttpStatus.CONFLICT,"INVALID_BOOKING_TRANSITION");
        if("IN_PROGRESS".equals(to)){
            OffsetDateTime locked=DbTime.toOffsetDateTime(b.get("pin_locked_until"));
            if(locked!=null&&locked.isAfter(OffsetDateTime.now()))throw new ApiException(HttpStatus.TOO_MANY_REQUESTS,"PIN_TEMPORARILY_LOCKED");
            boolean valid=pin!=null&&enc.matches(pin,(String)b.get("pin_hash"));
            if(!valid){
                int attempts=((Number)b.get("pin_failed_attempts")).intValue()+1;
                OffsetDateTime lock=attempts>=5?OffsetDateTime.now().plusMinutes(15):null;
                db.update("update scheduled_bookings set pin_failed_attempts=?,pin_locked_until=?,updated_at=now() where id=?",attempts,lock,id);
                throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,attempts>=5?"PIN_TEMPORARILY_LOCKED":"INVALID_PIN");
            }
            db.update("update scheduled_bookings set pin_failed_attempts=0,pin_locked_until=null where id=?",id);
            String method=db.queryForObject("select payment_method from scheduled_bookings where id=?",String.class,id);
            if("ONLINE".equals(method)){
                Integer paid=db.queryForObject("select count(*) from payments where booking_id=? and status='CAPTURED'",Integer.class,id);
                if(paid==0)throw new ApiException(HttpStatus.PAYMENT_REQUIRED,"PAYMENT_REQUIRED");
            }
        }
        db.update("update scheduled_bookings set status=?,updated_at=now() where id=?",to,id);
        event(id,"booking.status."+to.toLowerCase());
    }
    private UUID driver(){
        List<UUID>x=db.queryForList("select id from drivers where user_id=?",UUID.class,CurrentUser.id());
        if(x.isEmpty())throw new ApiException(HttpStatus.FORBIDDEN,"DRIVER_PROFILE_REQUIRED");
        return x.getFirst();
    }
    private void eligible(UUID d){
        Integer n=db.queryForObject("select count(*) from drivers where id=? and status='ACTIVE' and kyc_status='APPROVED' and marketplace_enabled=true",Integer.class,d);
        if(n==0)throw new ApiException(HttpStatus.FORBIDDEN,"DRIVER_NOT_ELIGIBLE");
    }
    private void conflict(UUID d,OffsetDateTime t){
        Integer n=db.queryForObject("select count(*) from scheduled_bookings where selected_driver_id=? and status in ('CONFIRMED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS') and scheduled_at between ? and ?",Integer.class,d,t.minusMinutes(90),t.plusMinutes(90));
        if(n>0)throw new ApiException(HttpStatus.CONFLICT,"DRIVER_SCHEDULE_CONFLICT");
    }
    private void owner(Map<String,Object>b){
        UUID u=CurrentUser.id();
        if(u.equals(b.get("creator_user_id")))return;
        if(b.get("partner_id")!=null){
            member((UUID)b.get("partner_id"),u);
            return;
        }
        throw new ApiException(HttpStatus.FORBIDDEN,"FORBIDDEN");
    }
    private void member(UUID p,UUID u){
        Integer n=db.queryForObject("select count(*) from partner_users where partner_id=? and user_id=? and status='ACTIVE'",Integer.class,p,u);
        if(n==0)throw new ApiException(HttpStatus.FORBIDDEN,"PARTNER_SCOPE_FORBIDDEN");
    }
    private void invoiceEligible(UUID p){
        if(p==null)throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"PARTNER_REQUIRED");
        Integer n=db.queryForObject("select count(*) from partner_organizations po join partner_invoice_accounts pia on pia.partner_id=po.id where po.id=? and po.status='APPROVED' and po.credit_status='APPROVED' and pia.status='ACTIVE' and pia.outstanding_minor<po.credit_limit_minor",Integer.class,p);
        if(n==0)throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"PARTNER_INVOICE_NOT_ELIGIBLE");
    }
    private int rate(UUID p){
        if(p!=null){
            List<Integer>x=db.queryForList("select commission_bps from commission_policy_versions where status='ACTIVE' and scope_type='PARTNER' and partner_id=? order by version_no desc limit 1",Integer.class,p);
            if(!x.isEmpty())return x.getFirst();
        }
        return db.queryForObject("select commission_bps from commission_policy_versions where status='ACTIVE' and scope_type='STANDARD' order by version_no desc limit 1",Integer.class);
    }
    private long commission(long p,int r){
        return BigDecimal.valueOf(p).multiply(BigDecimal.valueOf(r)).divide(BigDecimal.valueOf(10000),0,RoundingMode.HALF_UP).longValue();
    }
    private Map<String,Object> one(String q,Object...a){
        List<Map<String,Object>>x=db.queryForList(q,a);
        if(x.isEmpty())throw new ApiException(HttpStatus.NOT_FOUND,"NOT_FOUND");
        return x.getFirst();
    }
    private OffsetDateTime min(OffsetDateTime a,OffsetDateTime b){
        return a.isBefore(b)?a:b;
    }
    private void event(UUID id,String t){
        db.update("insert into outbox_events(aggregate_type,aggregate_id,event_type,payload) values ('BOOKING',?,?,jsonb_build_object('bookingId',?::text))",id,t,id);
    }
}
