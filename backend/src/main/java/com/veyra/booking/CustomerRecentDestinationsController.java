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
  public record Destination(@NotBlank @Size(max=500) String address,
      @NotNull @DecimalMin("-90") @DecimalMax("90") Double lat,
      @NotNull @DecimalMin("-180") @DecimalMax("180") Double lng) {}

  @GetMapping
  public List<Map<String,Object>> list(){
    return db.queryForList("select id,address,lat,lng,last_used_at from customer_recent_destinations "+
      "where user_id=? and last_used_at>now()-interval '90 days' order by last_used_at desc,id desc limit 20",CurrentUser.id());
  }

  @PostMapping
  @ResponseStatus(HttpStatus.CREATED)
  @Transactional
  public Map<String,Object> record(@Valid @RequestBody Destination input){
    UUID user=CurrentUser.id();
    String address=input.address().trim();
    double lat=Math.round(input.lat()*1_000_000d)/1_000_000d;
    double lng=Math.round(input.lng()*1_000_000d)/1_000_000d;
    db.queryForList("select pg_advisory_xact_lock(hashtextextended(?,0))","recent-destinations:"+user);
    UUID id=UUID.randomUUID();
    // UNIQUE constraint + upsert avoid duplicates even if callers race.
    UUID persisted=db.queryForObject(
      "insert into customer_recent_destinations(id,user_id,address,lat,lng) values(?,?,?,?,?) "+
      "on conflict(user_id,address,lat,lng) do update set last_used_at=now() returning id",
      UUID.class,id,user,address,lat,lng);
    db.update("delete from customer_recent_destinations where id in "+
      "(select id from customer_recent_destinations where user_id=? "+
      "and (last_used_at<=now()-interval '90 days' or id in "+
      "(select id from customer_recent_destinations where user_id=? "+
      "order by last_used_at desc,id desc offset 20)))",user,user);
    return Map.of("id",Objects.requireNonNull(persisted));
  }

  @DeleteMapping("/{id}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void delete(@PathVariable UUID id){
    db.update("delete from customer_recent_destinations where user_id=? and id=?",CurrentUser.id(),id);
  }

  @DeleteMapping
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void clear(){
    db.update("delete from customer_recent_destinations where user_id=?",CurrentUser.id());
  }
}
