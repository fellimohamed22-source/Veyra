package com.veyra.device;

import com.veyra.security.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

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
    db.update(
        "insert into user_devices(user_id,platform,push_token,device_name,last_seen_at,active) values (?,?,?,?,now(),true) " +
        "on conflict(push_token) do update set user_id=excluded.user_id,platform=excluded.platform," +
        "device_name=excluded.device_name,last_seen_at=now(),active=true",
        CurrentUser.id(),request.platform(),request.pushToken(),request.deviceName());
  }

  @DeleteMapping("/{id}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void deactivate(@PathVariable UUID id){
    db.update(
        "update user_devices set active=false where id=? and user_id=?",
        id,CurrentUser.id());
  }
}
