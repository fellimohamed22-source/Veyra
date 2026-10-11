package com.veyra.booking;

import com.veyra.security.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api/v1/me/recent-destinations")
public class CustomerRecentDestinationsController {
  private final JdbcTemplate db;
  public CustomerRecentDestinationsController(JdbcTemplate db){this.db=db;}

  public record Destination(
      @NotBlank @Size(max=500) String address,
      @NotNull @DecimalMin("-90") @DecimalMax("90") Double lat,
      @NotNull @DecimalMin("-180") @DecimalMax("180") Double lng) {}

  @GetMapping
  public List<Map<String,Object>> list(){
    UUID userId=CurrentUser.id();
    return db.queryForList(
      "select id,address,lat,lng,last_used_at from customer_recent_destinations " +
      "where user_id=? and last_used_at > now()-interval '90 days' " +
      "order by last_used_at desc,id desc limit 20",userId);
  }

  // Called only after explicit customer interaction (e.g. confirmed destination),
  // not by passive geolocation. Coordinates are rounded to 6 decimal places.
  @PostMapping
  @ResponseStatus(HttpStatus.CREATED)
  @Transactional
  public Map<String,Object> record(@Valid @RequestBody Destination destination){
    UUID userId=CurrentUser.id();
    String address=destination.address().trim();
    double lat=Math.round(destination.lat()*1_000_000d)/1_000_000d;
    double lng=Math.round(destination.lng()*1_000_000d)/1_000_000d;
    // Serialize simultaneous writes by the same user to preserve the cap.
    db.queryForList("select pg_advisory_xact_lock(hashtextextended(?,0))","recent-destinations:"+userId);
    db.update("delete from customer_recent_destinations where user_id=? and last_used_at <= now()-interval '90 days'",userId);
    List<UUID> existing=db.queryForList(
      "select id from customer_recent_destinations where user_id=? and address=? and lat=? and lng=? order by last_used_at desc limit 1",
      UUID.class,userId,address,lat,lng);
    UUID id;
    if(existing.isEmpty()){
      id=UUID.randomUUID();
      db.update("insert into customer_recent_destinations(id,user_id,address,lat,lng) values (?,?,?,?,?)",id,userId,address,lat,lng);
    }else{
      id=existing.getFirst();
      db.update("update customer_recent_destinations set last_used_at=now() where id=? and user_id=?",id,userId);
    }
    db.update("delete from customer_recent_destinations where id in (" +
      "select id from customer_recent_destinations where user_id=? " +
      "order by last_used_at desc,id desc offset 20)",userId);
    return Map.of("id",id);
  }

  @DeleteMapping("/{id}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void delete(@PathVariable UUID id){
    db.update("delete from customer_recent_destinations where id=? and user_id=?",id,CurrentUser.id());
  }

  @DeleteMapping
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void clear(){
    db.update("delete from customer_recent_destinations where user_id=?",CurrentUser.id());
  }
}
