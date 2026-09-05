package com.veyra.device;

import com.veyra.security.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/devices")
public class DeviceController {
  private final JdbcTemplate db;

  public DeviceController(JdbcTemplate db){
    this.db=db;
  }

  public record RegisterDevice(
      @NotBlank @Size(max=20) String platform,
      @NotBlank @Size(max=512) String pushToken,
      @Size(max=255) String deviceName){}

  @PostMapping
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void register(@Valid @RequestBody RegisterDevice request){
    UUID userId=CurrentUser.id();
    Integer existing=db.queryForObject(
        "select count(*) from user_devices where user_id=? and push_token=?",
        Integer.class,userId,request.pushToken());

    if(existing!=null && existing>0){
      db.update(
          "update user_devices set platform=?,device_name=?,last_seen_at=now(),active=true where user_id=? and push_token=?",
          request.platform(),request.deviceName(),userId,request.pushToken());
      return;
    }

    db.update(
        "insert into user_devices(user_id,platform,push_token,device_name,last_seen_at,active) values (?,?,?,?,now(),true)",
        userId,request.platform(),request.pushToken(),request.deviceName());
  }

  @DeleteMapping("/{id}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void deactivate(@PathVariable UUID id){
    db.update(
        "update user_devices set active=false where id=? and user_id=?",
        id,CurrentUser.id());
  }
}
