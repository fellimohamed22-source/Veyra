package com.veyra.auth;
import com.veyra.security.CurrentUser;import com.veyra.shared.ApiException;import com.veyra.storage.*;
import jakarta.validation.Valid;import jakarta.validation.constraints.*;import org.springframework.http.*;import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.security.crypto.password.PasswordEncoder;import org.springframework.web.bind.annotation.*;import org.springframework.web.multipart.MultipartFile;
import java.io.*;import java.util.*;
@RestController @RequestMapping("/api/v1") public class MeController{
 private final JdbcTemplate db;private final PasswordEncoder encoder;private final FileStorageProvider storage;
 public MeController(JdbcTemplate d,PasswordEncoder e,FileStorageProvider s){db=d;encoder=e;storage=s;}
 public record Profile(@NotBlank @Size(max=100) String firstName,@Size(max=100) String lastName,@Size(max=32) String phone){}
 public record PasswordChange(@NotBlank String currentPassword,@Size(min=10,max=128) String newPassword){}
 @GetMapping("/me") public Map<String,Object> me(){UUID id=CurrentUser.id();Map<String,Object> u=db.queryForMap("select id,first_name,last_name,email::text as email,phone,status,locale,timezone,avatar_storage_key is not null as has_avatar from users where id=?",id);Map<String,Object> r=new LinkedHashMap<>(u);r.put("roles",db.queryForList("select ro.code from roles ro join user_roles ur on ur.role_id=ro.id where ur.user_id=? order by ro.code",String.class,id));Map<String,Object> q=db.queryForMap("select coalesce(round(avg(score)::numeric,2),0) average,count(*) count from ride_ratings where rated_user_id=?",id);r.put("rating_average",q.get("average"));r.put("rating_count",q.get("count"));return r;}
 @PatchMapping("/me") public Map<String,Object> update(@Valid @RequestBody Profile p){db.update("update users set first_name=?,last_name=?,phone=?,updated_at=now() where id=?",p.firstName().trim(),blank(p.lastName()),blank(p.phone()),CurrentUser.id());return me();}
 @PostMapping("/me/password") @ResponseStatus(HttpStatus.NO_CONTENT) public void password(@Valid @RequestBody PasswordChange p){UUID id=CurrentUser.id();String h=db.queryForObject("select password_hash from users where id=?",String.class,id);if(h==null||!encoder.matches(p.currentPassword(),h))throw new ApiException(HttpStatus.UNAUTHORIZED,"CURRENT_PASSWORD_INVALID");db.update("update users set password_hash=?,updated_at=now() where id=?",encoder.encode(p.newPassword()),id);db.update("update user_sessions set revoked_at=now() where user_id=? and revoked_at is null",id);}
 @PostMapping(value="/me/avatar",consumes=MediaType.MULTIPART_FORM_DATA_VALUE) public Map<String,Object> avatar(@RequestParam MultipartFile file)throws IOException{if(file.getContentType()==null||!Set.of("image/jpeg","image/png").contains(file.getContentType()))throw new ApiException(HttpStatus.BAD_REQUEST,"AVATAR_IMAGE_REQUIRED");StoredFile n;try{n=storage.store(file.getInputStream(),file.getOriginalFilename(),file.getContentType(),file.getSize());}catch(IllegalArgumentException e){
  // Real bug fixed here, confirmed by the exact 500 the user's own
  // diagnostic banner captured (DioException 500 from Api.uploadAvatar):
  // FilesystemStorageProvider.store() throws a plain
  // IllegalArgumentException("INVALID_FILE_SIZE"/"INVALID_FILE_TYPE") --
  // reasonable for a low-level storage provider that has no notion of
  // HTTP status codes -- but ApiExceptionHandler only has a dedicated
  // @ExceptionHandler for ApiException; anything else (including this)
  // falls through to the generic Exception handler and comes back as an
  // opaque 500, exactly matching what the user saw. A modern phone
  // camera photo routinely exceeds the configured 10MB limit
  // (veyra.storage.max-file-size-mb), making this a very plausible,
  // easy-to-hit real-world case, not an edge case. Translated to a
  // proper 400 here, at the controller layer (which knows about HTTP
  // semantics), rather than making the storage provider itself
  // HTTP-aware.
  throw new ApiException(HttpStatus.BAD_REQUEST,e.getMessage());
}List<String> old=db.queryForList("select avatar_storage_key from users where id=? and avatar_storage_key is not null",String.class,CurrentUser.id());db.update("update users set avatar_storage_key=?,avatar_content_type=?,updated_at=now() where id=?",n.storageKey(),n.contentType(),CurrentUser.id());if(!old.isEmpty()&&!old.getFirst().equals(n.storageKey()))try{storage.delete(old.getFirst());}catch(Exception ignored){}return me();}
 @GetMapping("/me/avatar") public ResponseEntity<byte[]> avatarContent()throws IOException{Map<String,Object>x=db.queryForMap("select avatar_storage_key,avatar_content_type from users where id=?",CurrentUser.id());String k=(String)x.get("avatar_storage_key");if(k==null)throw new ApiException(HttpStatus.NOT_FOUND,"AVATAR_NOT_FOUND");return ResponseEntity.ok().contentType(MediaType.parseMediaType((String)x.get("avatar_content_type"))).body(storage.load(k).readAllBytes());}
 private String blank(String s){return s==null||s.trim().isEmpty()?null:s.trim();}
}