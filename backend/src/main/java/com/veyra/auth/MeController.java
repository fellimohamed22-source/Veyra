package com.veyra.auth;

import com.veyra.security.CurrentUser;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Size;

import java.util.*;

@RestController
@RequestMapping("/api/v1")
public class MeController {
  private final JdbcTemplate db;

  public MeController(JdbcTemplate db){this.db=db;}

  public record UpdateProfile(
      @Size(min=1,max=100) String firstName,
      @Size(max=100) String lastName,
      @Size(max=32) String phone){}

  @GetMapping("/me")
  public Map<String,Object> me(){
    UUID userId=CurrentUser.id();
    Map<String,Object> user=db.queryForMap(
        "select id,first_name,last_name,email::text as email,phone,status,locale,timezone from users where id=?",
        userId);
    List<String> roles=db.queryForList(
        "select r.code from roles r join user_roles ur on ur.role_id=r.id where ur.user_id=? order by r.code",
        String.class,userId);
    Map<String,Object> result=new LinkedHashMap<>(user);
    result.put("roles",roles);
    return result;
  }

  @PatchMapping("/me")
  public Map<String,Object> update(@Valid @RequestBody UpdateProfile request){
    UUID userId=CurrentUser.id();
    Map<String,Object> current=db.queryForMap(
        "select first_name,last_name,phone from users where id=?",userId);
    String first=request.firstName()==null
        ?String.valueOf(current.get("first_name"))
        :request.firstName().trim();
    if(first.isBlank()) throw new IllegalArgumentException("firstName");
    String last=request.lastName()==null
        ?(current.get("last_name")==null?null:String.valueOf(current.get("last_name")))
        :request.lastName().trim();
    String phone=request.phone()==null
        ?(current.get("phone")==null?null:String.valueOf(current.get("phone")))
        :request.phone().trim();
    if(phone!=null&&phone.isBlank())phone=null;
    db.update(
        "update users set first_name=?,last_name=?,phone=?,updated_at=now() where id=?",
        first,last,phone,userId);
    return me();
  }
}
