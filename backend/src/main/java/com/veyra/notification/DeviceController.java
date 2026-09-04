package com.veyra.notification;

import com.veyra.security.CurrentUser;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/devices")
public class DeviceController {
  private final JdbcTemplate db;
  public DeviceController(JdbcTemplate db){this.db=db;}

  public record RegisterDevice(String platform,String pushToken,String deviceName){}

  @PostMapping
  public ResponseEntity<Void> register(@RequestBody RegisterDevice request){
    if(request.pushToken()==null || request.pushToken().isBlank()) {
      return ResponseEntity.badRequest().build();
    }
    UUID userId=CurrentUser.id();
    db.update(
      "insert into user_devices(user_id,platform,push_token,device_name,active,last_seen_at) " +
      "values (?,?,?,?,true,now()) on conflict(push_token) do update set user_id=excluded.user_id," +
      "platform=excluded.platform,device_name=excluded.device_name,active=true,last_seen_at=now()",
      userId,request.platform(),request.pushToken(),request.deviceName());
    return ResponseEntity.noContent().build();
  }

  @DeleteMapping("/{token}")
  public ResponseEntity<Void> disable(@PathVariable String token){
    db.update("update user_devices set active=false where user_id=? and push_token=?",CurrentUser.id(),token);
    return ResponseEntity.noContent().build();
  }
}
