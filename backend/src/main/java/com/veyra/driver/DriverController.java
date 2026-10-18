package com.veyra.driver;import com.veyra.security.CurrentUser;import com.veyra.storage.*;import org.springframework.http.*;import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.web.bind.annotation.*;import org.springframework.web.multipart.MultipartFile;import java.io.*;import java.util.*;
@RestController @RequestMapping("/api/v1/driver") public class DriverController{private final JdbcTemplate db;private final FileStorageProvider fs;public DriverController(JdbcTemplate d,FileStorageProvider f){db=d;fs=f;}@PostMapping("/profile")ResponseEntity<Map<String,UUID>>profile(){UUID u=CurrentUser.id();List<UUID>x=db.queryForList("select id from drivers where user_id=?",UUID.class,u);if(!x.isEmpty())return ResponseEntity.ok(Map.of("driverId",x.getFirst()));UUID id=UUID.randomUUID();db.update("insert into drivers(id,user_id) values (?,?)",id,u);db.update("insert into user_roles(user_id,role_id) select ?,id from roles where code='DRIVER' on conflict do nothing",u);return ResponseEntity.status(201).body(Map.of("driverId",id));}@GetMapping("/documents")List<Map<String,Object>>documents(){return db.queryForList("select dd.id,dd.type,dd.status,dd.original_filename,dd.expires_at,dd.rejection_reason_code,dd.created_at from driver_documents dd join drivers d on d.id=dd.driver_id where d.user_id=? and dd.status<>'SUPERSEDED' order by dd.created_at desc",CurrentUser.id());}
  static final Set<String> SIDES=Set.of("FRONT","BACK");
  static final Set<String> IDENTITY_SUBTYPES=Set.of("ID_CARD","PASSPORT","RESIDENCE_PERMIT");

  /**
   * Upload one document page. Recto and verso are kept side by side (a
   * new upload only supersedes the same type AND side). A first dossier
   * stays a draft until « Envoyer mon dossier » (onboarding/submit); a
   * replacement after review sends the dossier back for review.
   */
  @PostMapping("/documents")
  ResponseEntity<Map<String,UUID>>doc(@RequestParam String type,@RequestParam MultipartFile file,
      @RequestParam(required=false) String side,@RequestParam(required=false) String subtype,
      @RequestParam(required=false) @org.springframework.format.annotation.DateTimeFormat(iso=org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate expiresAt)throws IOException{
    String s1=side==null?null:side.toUpperCase(Locale.ROOT);
    if(s1!=null&&!SIDES.contains(s1))throw new com.veyra.shared.ApiException(HttpStatus.BAD_REQUEST,"DOCUMENT_SIDE_INVALID");
    String sub=subtype==null?null:subtype.toUpperCase(Locale.ROOT);
    if(sub!=null&&"IDENTITY".equals(type)&&!IDENTITY_SUBTYPES.contains(sub))throw new com.veyra.shared.ApiException(HttpStatus.BAD_REQUEST,"DOCUMENT_SUBTYPE_INVALID");
    if(expiresAt!=null&&expiresAt.isBefore(java.time.LocalDate.now()))throw new com.veyra.shared.ApiException(HttpStatus.BAD_REQUEST,"DOCUMENT_EXPIRED");
    UUID d=db.queryForObject("select id from drivers where user_id=?",UUID.class,CurrentUser.id());
    StoredFile s=fs.store(file.getInputStream(),file.getOriginalFilename(),file.getContentType(),file.getSize());
    db.update("update driver_documents set status='SUPERSEDED' where driver_id=? and type=? and side is not distinct from ? and status<>'SUPERSEDED'",d,type,s1);
    UUID id=UUID.randomUUID();
    db.update("insert into driver_documents(id,driver_id,type,storage_key,original_filename,content_type,side,subtype,expires_at) values (?,?,?,?,?,?,?,?,?)",id,d,type,s.storageKey(),s.originalFilename(),s.contentType(),s1,sub,expiresAt);
    db.update("update drivers set kyc_status='SUBMITTED' where id=? and kyc_status in ('REJECTED','UNDER_REVIEW','SUBMITTED')",d);
    return ResponseEntity.status(201).body(Map.of("documentId",id));
  }
}