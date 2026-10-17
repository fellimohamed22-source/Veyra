package com.veyra.admin;

import com.fasterxml.jackson.databind.ObjectMapper;
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
 * ADM-10: business parameters (lead time, offer window, pickup radius...)
 * changed without redeploying, within bounds stored with each setting,
 * every change audited with before/after and justification.
 */
@RestController
@RequestMapping("/api/v1/admin/settings")
@PreAuthorize("hasRole('ADMIN')")
public class PlatformSettingsController {
  private static final ObjectMapper JSON=new ObjectMapper();
  private final JdbcTemplate db;

  public PlatformSettingsController(JdbcTemplate db){
    this.db=db;
  }

  public record Change(@NotNull Long value,@NotBlank @Size(max=500) String justification){}

  @GetMapping
  public List<Map<String,Object>> list(){
    return db.queryForList("select setting_key,value_number,min_value,max_value,description,updated_by,updated_at from platform_settings order by setting_key");
  }

  @PutMapping("/{key}")
  @Transactional
  public Map<String,Object> update(@PathVariable String key,@Valid @RequestBody Change c){
    List<Map<String,Object>> rows=db.queryForList("select value_number,min_value,max_value from platform_settings where setting_key=? for update",key);
    if(rows.isEmpty())throw new ApiException(HttpStatus.NOT_FOUND,"SETTING_NOT_FOUND");
    Map<String,Object> current=rows.getFirst();
    long min=((Number)current.get("min_value")).longValue(),max=((Number)current.get("max_value")).longValue();
    if(c.value()<min||c.value()>max)throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"SETTING_OUT_OF_RANGE");
    db.update("update platform_settings set value_number=?,updated_by=?,updated_at=now() where setting_key=?",c.value(),CurrentUser.id(),key);
    Map<String,Object> meta=new LinkedHashMap<>();
    meta.put("key",key);
    meta.put("before",current.get("value_number"));
    meta.put("after",c.value());
    meta.put("justification",c.justification());
    String json;
    try{json=JSON.writeValueAsString(meta);}catch(Exception e){json="{}";}
    db.update("insert into audit_logs(actor_id,actor_type,action,entity_type,metadata) values (?,'ADMIN','PLATFORM_SETTING_UPDATED','PLATFORM_SETTING',?::jsonb)",
        CurrentUser.id(),json);
    return Map.of("key",key,"value",c.value());
  }
}
