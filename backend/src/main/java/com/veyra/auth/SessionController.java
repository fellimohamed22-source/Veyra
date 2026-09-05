package com.veyra.auth;
import com.veyra.shared.ApiException;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.*;
import java.util.*;
@RestController @RequestMapping("/api/v1/auth")public class SessionController{
    private final JdbcTemplate db;
    private final JwtService jwt;
    private final SecureRandom rnd=new SecureRandom();
    public SessionController(JdbcTemplate d,JwtService j){
        db=d;
        jwt=j;
    }
    public record Req(String refreshToken,String deviceName){
    }
    public record Resp(String accessToken,String refreshToken,UUID userId){
    }
    @PostMapping("/refresh")Resp refresh(@RequestBody Req r){
        String h=sha(r.refreshToken());
        List<Map<String,Object>>x=db.queryForList("select s.id,s.user_id,u.email from user_sessions s join users u on u.id=s.user_id where s.refresh_token_hash=? and s.revoked_at is null and s.expires_at>now() for update",h);
        if(x.isEmpty())throw new ApiException(HttpStatus.UNAUTHORIZED,"INVALID_REFRESH_TOKEN");
        Map<String,Object>s=x.getFirst();
        db.update("update user_sessions set revoked_at=now() where id=?",s.get("id"));
        UUID u=(UUID)s.get("user_id");
        List<String>roles=db.queryForList("select r.code from roles r join user_roles ur on ur.role_id=r.id where ur.user_id=?",String.class,u);
        String fresh=token();
        db.update("insert into user_sessions(user_id,refresh_token_hash,device_name,expires_at) values (?,?,?,?)",u,sha(fresh),r.deviceName(),OffsetDateTime.now().plusDays(30));
            return new Resp(jwt.issue(u,
            (String)s.get("email"),
        roles),fresh,u);
    }
    @PostMapping("/logout")ResponseEntity<Void>logout(@RequestBody Req r){
        db.update("update user_sessions set revoked_at=now() where refresh_token_hash=? and revoked_at is null",sha(r.refreshToken()));
        return ResponseEntity.noContent().build();
    }
    private String token(){
        byte[]b=new byte[48];
        rnd.nextBytes(b);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(b);
    }
    private String sha(String s){
        try{
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8)));
        }
        catch(Exception e){
            throw new IllegalStateException(e);
        }
    }
}
