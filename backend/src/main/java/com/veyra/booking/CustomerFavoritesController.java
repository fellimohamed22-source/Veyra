package com.veyra.booking;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api/v1/me")
public class CustomerFavoritesController {
  private final JdbcTemplate db;
  public CustomerFavoritesController(JdbcTemplate db){this.db=db;}

  public record Address(@NotBlank @Size(max=80) String label,
      @NotBlank @Size(max=500) String address,
      @NotNull @DecimalMin("-90") @DecimalMax("90") Double lat,
      @NotNull @DecimalMin("-180") @DecimalMax("180") Double lng) {}

  @GetMapping("/addresses")
  public List<Map<String,Object>> addresses(){
    return db.queryForList("select id,label,address,lat,lng from customer_saved_addresses where user_id=? order by label,id",CurrentUser.id());
  }

  @PostMapping("/addresses")
  public Map<String,Object> addAddress(@Valid @RequestBody Address address){
    UUID id=UUID.randomUUID();
    db.update("insert into customer_saved_addresses(id,user_id,label,address,lat,lng) values (?,?,?,?,?,?)",id,CurrentUser.id(),address.label().trim(),address.address().trim(),address.lat(),address.lng());
    return Map.of("id",id);
  }

  @PutMapping("/addresses/{id}")
  public void updateAddress(@PathVariable UUID id,@Valid @RequestBody Address address){
    requireChanged(db.update("update customer_saved_addresses set label=?,address=?,lat=?,lng=? where id=? and user_id=?",address.label().trim(),address.address().trim(),address.lat(),address.lng(),id,CurrentUser.id()));
  }

  @DeleteMapping("/addresses/{id}")
  public void deleteAddress(@PathVariable UUID id){
    requireChanged(db.update("delete from customer_saved_addresses where id=? and user_id=?",id,CurrentUser.id()));
  }

  @GetMapping("/favorite-drivers")
  public List<Map<String,Object>> drivers(){
    return db.queryForList("select f.driver_id,f.booking_id,u.first_name,u.last_name,d.rating,v.brand,v.model,v.color,vc.display_name as category_name,f.created_at from customer_favorite_drivers f join drivers d on d.id=f.driver_id join users u on u.id=d.user_id left join lateral (select * from vehicles where driver_id=d.id and status='APPROVED' order by id limit 1) v on true left join vehicle_categories vc on vc.id=v.category_id where f.user_id=? order by f.created_at desc",CurrentUser.id());
  }

  @PutMapping("/favorite-drivers/from-booking/{id}")
  public void addDriver(@PathVariable UUID id){
    List<UUID> selected=db.queryForList("select selected_driver_id from scheduled_bookings where id=? and creator_user_id=? and status in ('COMPLETED','CLOSED') and selected_driver_id is not null",UUID.class,id,CurrentUser.id());
    if(selected.isEmpty())throw new ApiException(HttpStatus.NOT_FOUND,"COMPLETED_BOOKING_REQUIRED");
    db.update("insert into customer_favorite_drivers(user_id,driver_id,booking_id) values (?,?,?) on conflict(user_id,driver_id) do update set booking_id=excluded.booking_id",CurrentUser.id(),selected.getFirst(),id);
  }

  @DeleteMapping("/favorite-drivers/{id}")
  public void deleteDriver(@PathVariable UUID id){
    db.update("delete from customer_favorite_drivers where driver_id=? and user_id=?",id,CurrentUser.id());
  }

  private void requireChanged(int count){if(count==0)throw new ApiException(HttpStatus.NOT_FOUND,"NOT_FOUND");}
}
