package com.veyra.commission;

import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.*;

/**
 * V4 commission engine (DEC-01 method A, DEC-02/03 rules in database).
 *
 * The commission belongs to the booking account (creator), never to the
 * passenger or payer. Resolution picks the single most specific ACTIVE,
 * currently effective rule:
 * USER > PARTNER > PARTNER_CATEGORY > PROFILE > STANDARD.
 * USER rules apply to CLIENT bookings only; for PARTNER bookings the
 * organisation is the booking account.
 *
 * Method A: commission = HALF_UP(driverPrice x bps / 10000) + fixed,
 * clamped to [min, max]; customer total = driver price + commission.
 * All amounts in minor units with exact arithmetic.
 *
 * Plain JDBC on purpose (no Spring wiring) so controllers can build it
 * from their JdbcTemplate without changing their constructors.
 */
public class CommissionEngine {
  public static final List<String> SCOPE_PRIORITY=List.of("USER","PARTNER","PARTNER_CATEGORY","PROFILE","STANDARD");

  private final JdbcTemplate db;

  public CommissionEngine(JdbcTemplate db){
    this.db=db;
  }

  /** Who the booking account is. bookerType: CLIENT or PARTNER. */
  public record Context(String bookerType,UUID userId,UUID partnerId,String partnerCategory){
    public static Context client(UUID userId){return new Context("CLIENT",userId,null,null);}
    public static Context partner(UUID partnerId,String category){return new Context("PARTNER",null,partnerId,category);}
  }

  public record Rule(UUID id,String scopeType,int rateBps,long fixedMinor,Long minMinor,Long maxMinor){}

  public record Quote(UUID policyId,String scopeType,int rateBps,long commissionMinor,long totalMinor){
    public void putInto(Map<String,Object> m){
      m.put("commissionRateBps",rateBps);
      m.put("commissionMinor",commissionMinor);
      m.put("customerTotalMinor",totalMinor);
    }
  }

  static final String RESOLVE_SQL=
      "select id,scope_type,commission_bps,fixed_minor,min_commission_minor,max_commission_minor " +
      "from commission_policy_versions where status='ACTIVE' " +
      "and (effective_from is null or effective_from<=now()) and (effective_to is null or effective_to>now()) " +
      "and (scope_type='STANDARD' " +
      "or (scope_type='PROFILE' and profile_type=?) " +
      "or (scope_type='PARTNER_CATEGORY' and ?::varchar is not null and partner_category=?) " +
      "or (scope_type='PARTNER' and ?::uuid is not null and partner_id=?) " +
      "or (scope_type='USER' and ?::uuid is not null and user_id=?)) " +
      "order by case scope_type when 'USER' then 0 when 'PARTNER' then 1 when 'PARTNER_CATEGORY' then 2 when 'PROFILE' then 3 else 4 end," +
      "effective_from desc nulls last,version_no desc limit 1";

  public Rule resolve(Context ctx){
    boolean partnerBooking="PARTNER".equals(ctx.bookerType());
    UUID userId=partnerBooking?null:ctx.userId();
    UUID partnerId=partnerBooking?ctx.partnerId():null;
    String category=partnerBooking?ctx.partnerCategory():null;
    List<Map<String,Object>> rows=db.queryForList(RESOLVE_SQL,
        partnerBooking?"PARTNER":"CLIENT",category,category,partnerId,partnerId,userId,userId);
    if(rows.isEmpty())throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"COMMISSION_POLICY_MISSING");
    Map<String,Object> r=rows.getFirst();
    return new Rule((UUID)r.get("id"),(String)r.get("scope_type"),((Number)r.get("commission_bps")).intValue(),
        r.get("fixed_minor")==null?0L:((Number)r.get("fixed_minor")).longValue(),
        toLong(r.get("min_commission_minor")),toLong(r.get("max_commission_minor")));
  }

  public Quote quote(Context ctx,long driverPriceMinor){
    Rule rule=resolve(ctx);
    long c=commission(driverPriceMinor,rule);
    return new Quote(rule.id(),rule.scopeType(),rule.rateBps(),c,Math.addExact(driverPriceMinor,c));
  }

  /** Booking account of an existing booking. */
  public Context contextForBooking(UUID bookingId){
    List<Map<String,Object>> rows=db.queryForList(
        "select sb.creator_type,sb.creator_user_id,sb.partner_id,po.partner_type from scheduled_bookings sb " +
        "left join partner_organizations po on po.id=sb.partner_id where sb.id=?",bookingId);
    if(rows.isEmpty())throw new ApiException(HttpStatus.NOT_FOUND,"NOT_FOUND");
    Map<String,Object> b=rows.getFirst();
    if(b.get("partner_id")!=null)return Context.partner((UUID)b.get("partner_id"),(String)b.get("partner_type"));
    return Context.client((UUID)b.get("creator_user_id"));
  }

  public Quote quoteForBooking(UUID bookingId,long driverPriceMinor){
    return quote(contextForBooking(bookingId),driverPriceMinor);
  }

  public static long commission(long driverPriceMinor,Rule rule){
    long c=BigDecimal.valueOf(driverPriceMinor).multiply(BigDecimal.valueOf(rule.rateBps()))
        .divide(BigDecimal.valueOf(10000),0,RoundingMode.HALF_UP).longValueExact();
    c=Math.addExact(c,rule.fixedMinor());
    if(rule.minMinor()!=null)c=Math.max(c,rule.minMinor());
    if(rule.maxMinor()!=null)c=Math.min(c,rule.maxMinor());
    return c;
  }

  private static Long toLong(Object v){
    return v==null?null:((Number)v).longValue();
  }
}
