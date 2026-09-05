package com.veyra.auth;

import com.veyra.security.CurrentUser;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1")
public class MeController {
  private final JdbcTemplate db;

  public MeController(JdbcTemplate db){this.db=db;}

  @GetMapping("/me")
  public Map<String,Object> me(){
    UUID userId=CurrentUser.id();
    Map<String,Object> user=db.queryForMap(
        "select id,first_name,last_name,email,phone,status,locale,timezone from users where id=?",
        userId);
    List<String> roles=db.queryForList(
        "select r.code from roles r join user_roles ur on ur.role_id=r.id where ur.user_id=? order by r.code",
        String.class,userId);
    Map<String,Object> result=new LinkedHashMap<>(user);
    result.put("roles",roles);
    return result;
  }
}
