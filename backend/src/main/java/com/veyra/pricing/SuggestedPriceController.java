package com.veyra.pricing;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.veyra.provider.RoutingProvider;
import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.*;

/**
 * DEC-18: suggested net price shown to the driver next to the price field,
 * and the admin grid it is computed from. No grid row = nothing suggested.
 */
@RestController
@RequestMapping("/api/v1")
public class SuggestedPriceController {
  private static final ObjectMapper JSON=new ObjectMapper();
  private final JdbcTemplate db;
  private final RoutingProvider routing;

  public SuggestedPriceController(JdbcTemplate db,RoutingProvider routing){
    this.db=db;
    this.routing=routing;
  }

  @GetMapping("/driver/opportunities/{bookingId}/suggested-price")
  public Map<String,Object> suggested(@PathVariable UUID bookingId){
    List<UUID> driver=db.queryForList("select id from drivers where user_id=? and status='ACTIVE' and kyc_status='APPROVED' and marketplace_enabled=true",UUID.class,CurrentUser.id());
    if(driver.isEmpty())throw new ApiException(HttpStatus.FORBIDDEN,"DRIVER_NOT_ELIGIBLE");
    List<Map<String,Object>> rows=db.queryForList(
        "select ST_Y(sb.pickup::geometry) as plat,ST_X(sb.pickup::geometry) as plng,ST_Y(sb.dropoff::geometry) as dlat,ST_X(sb.dropoff::geometry) as dlng," +
        "g.base_minor,g.per_km_minor,g.per_minute_minor,g.minimum_minor,g.spread_bps,g.currency " +
        "from scheduled_bookings sb join suggested_price_grid g on g.category_id=sb.category_id and g.active " +
        "where sb.id=? and sb.status in ('OPEN_FOR_OFFERS','OFFERS_RECEIVED')",bookingId);
    if(rows.isEmpty())return Map.of("available",false);
    Map<String,Object> r=rows.getFirst();
    RoutingProvider.Route route;
    try{
      route=routing.route(num(r,"plat"),num(r,"plng"),num(r,"dlat"),num(r,"dlng"));
    }catch(RuntimeException e){
      // A suggestion is only an aid: never block the offer screen on routing.
      return Map.of("available",false);
    }
    var range=SuggestedPrice.compute(new SuggestedPrice.Grid(lng(r,"base_minor"),lng(r,"per_km_minor"),lng(r,"per_minute_minor"),
        lng(r,"minimum_minor"),((Number)r.get("spread_bps")).intValue()),route.distanceMeters(),route.durationSeconds());
    Map<String,Object> result=new LinkedHashMap<>();
    result.put("available",true);
    result.put("netLowMinor",range.lowMinor());
    result.put("netHighMinor",range.highMinor());
    result.put("netCenterMinor",range.centerMinor());
    result.put("currency",r.get("currency"));
    result.put("distanceMeters",route.distanceMeters());
    result.put("durationSeconds",route.durationSeconds());
    return result;
  }

  public record GridRow(@NotNull @Min(0) Long baseMinor,@NotNull @Min(0) Long perKmMinor,@NotNull @Min(0) Long perMinuteMinor,
                        @Min(0) Long minimumMinor,@Min(0) @Max(5000) Integer spreadBps,Boolean active,
                        @NotBlank @Size(max=500) String justification){}

  @GetMapping("/admin/suggested-price-grid")
  @PreAuthorize("hasAnyRole('ADMIN','FINANCE')")
  public List<Map<String,Object>> grid(){
    return db.queryForList("select vc.id as category_id,vc.code,vc.display_name,g.base_minor,g.per_km_minor,g.per_minute_minor,g.minimum_minor," +
        "g.spread_bps,g.currency,g.active,g.updated_at from vehicle_categories vc left join suggested_price_grid g on g.category_id=vc.id order by vc.display_name");
  }

  @PutMapping("/admin/suggested-price-grid/{categoryId}")
  @PreAuthorize("hasAnyRole('ADMIN','FINANCE')")
  @Transactional
  public Map<String,Object> upsert(@PathVariable UUID categoryId,@Valid @RequestBody GridRow g){
    Integer exists=db.queryForObject("select count(*) from vehicle_categories where id=?",Integer.class,categoryId);
    if(exists==null||exists==0)throw new ApiException(HttpStatus.NOT_FOUND,"CATEGORY_NOT_FOUND");
    List<Map<String,Object>> before=db.queryForList("select base_minor,per_km_minor,per_minute_minor,minimum_minor,spread_bps,active from suggested_price_grid where category_id=?",categoryId);
    long minimum=g.minimumMinor()==null?0:g.minimumMinor();
    int spread=g.spreadBps()==null?1000:g.spreadBps();
    boolean active=g.active()==null||g.active();
    db.update("insert into suggested_price_grid(category_id,base_minor,per_km_minor,per_minute_minor,minimum_minor,spread_bps,active,updated_by,updated_at) " +
        "values (?,?,?,?,?,?,?,?,now()) on conflict (category_id) do update set base_minor=excluded.base_minor,per_km_minor=excluded.per_km_minor," +
        "per_minute_minor=excluded.per_minute_minor,minimum_minor=excluded.minimum_minor,spread_bps=excluded.spread_bps,active=excluded.active," +
        "updated_by=excluded.updated_by,updated_at=now()",
        categoryId,g.baseMinor(),g.perKmMinor(),g.perMinuteMinor(),minimum,spread,active,CurrentUser.id());
    Map<String,Object> meta=new LinkedHashMap<>();
    meta.put("before",before.isEmpty()?null:before.getFirst());
    meta.put("after",Map.of("baseMinor",g.baseMinor(),"perKmMinor",g.perKmMinor(),"perMinuteMinor",g.perMinuteMinor(),"minimumMinor",minimum,"spreadBps",spread,"active",active));
    meta.put("justification",g.justification());
    String json;
    try{json=JSON.writeValueAsString(meta);}catch(Exception e){json="{}";}
    db.update("insert into audit_logs(actor_id,actor_type,action,entity_type,entity_id,metadata) values (?,'ADMIN','SUGGESTED_PRICE_GRID_UPDATED','VEHICLE_CATEGORY',?,?::jsonb)",
        CurrentUser.id(),categoryId,json);
    return Map.of("categoryId",categoryId,"active",active);
  }

  private static double num(Map<String,Object> r,String k){return ((Number)r.get(k)).doubleValue();}
  private static long lng(Map<String,Object> r,String k){return ((Number)r.get(k)).longValue();}
}
