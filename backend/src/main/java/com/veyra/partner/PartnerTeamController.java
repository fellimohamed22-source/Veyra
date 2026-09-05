package com.veyra.partner;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/partner/{partnerId}/team")
public class PartnerTeamController {
  private final JdbcTemplate db;

  public PartnerTeamController(JdbcTemplate db){ this.db=db; }

  public record Add(UUID userId,String role){}

  @GetMapping
  public List<Map<String,Object>> list(@PathVariable UUID partnerId){
    owner(partnerId);
    return db.queryForList(
        "select pu.id,pu.user_id,pu.partner_role,pu.status,u.email,u.first_name,u.last_name " +
        "from partner_users pu join users u on u.id=pu.user_id where pu.partner_id=?",
        partnerId);
  }

  @PostMapping
  public void add(@PathVariable UUID partnerId,@RequestBody Add request){
    owner(partnerId);
    if(request.userId()==null || request.role()==null ||
        !Set.of("PARTNER_OWNER","PARTNER_STAFF","PARTNER_FINANCE").contains(request.role())){
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"INVALID_PARTNER_TEAM_MEMBER");
    }
    Integer userExists=db.queryForObject(
        "select count(*) from users where id=? and status='ACTIVE'",
        Integer.class,request.userId());
    if(userExists==null||userExists==0){
      throw new ApiException(HttpStatus.NOT_FOUND,"USER_NOT_FOUND");
    }
    db.update(
        "insert into partner_users(partner_id,user_id,partner_role) values (?,?,?) " +
        "on conflict(partner_id,user_id) do update set partner_role=excluded.partner_role,status='ACTIVE'",
        partnerId,request.userId(),request.role());
  }

  private void owner(UUID partnerId){
    Integer count=db.queryForObject(
        "select count(*) from partner_users where partner_id=? and user_id=? " +
        "and partner_role='PARTNER_OWNER' and status='ACTIVE'",
        Integer.class,partnerId,CurrentUser.id());
    if(count==null||count==0){
      throw new ApiException(HttpStatus.FORBIDDEN,"PARTNER_OWNER_REQUIRED");
    }
  }
}
