package com.veyra.admin;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import java.util.*;
@RestController
@RequestMapping("/api/v1/admin/audit")
@PreAuthorize("hasRole('ADMIN')")
public class AuditAspectController {
  private final JdbcTemplate db;
  public AuditAspectController(JdbcTemplate db){this.db=db;}
  @GetMapping
  public List<Map<String,Object>> logs(@RequestParam(defaultValue="100") int limit){
    int safe=Math.max(1,Math.min(limit,500));
    return db.queryForList("select actor_id,actor_type,action,entity_type,entity_id,metadata,created_at from audit_logs order by created_at desc limit "+safe);
  }
}
