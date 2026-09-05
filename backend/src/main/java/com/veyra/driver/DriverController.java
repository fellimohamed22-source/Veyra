package com.veyra.driver;
import com.veyra.security.CurrentUser;
import com.veyra.storage.*;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import java.io.*;
import java.util.*;
@RestController @RequestMapping("/api/v1/driver") public class DriverController{
    private final JdbcTemplate db;
    private final FileStorageProvider fs;
    public DriverController(JdbcTemplate d,FileStorageProvider f){
        db=d;
        fs=f;
    }
    @PostMapping("/profile")ResponseEntity<Map<String,UUID>>profile(){
        UUID u=CurrentUser.id();
        List<UUID>x=db.queryForList("select id from drivers where user_id=?",UUID.class,u);
            if(!x.isEmpty())return ResponseEntity.ok(Map.of("driverId",
        x.getFirst()));
        UUID id=UUID.randomUUID();
        db.update("insert into drivers(id,user_id) values (?,?)",id,u);
        db.update("insert into user_roles(user_id,role_id) select ?,id from roles where code='DRIVER' on conflict do nothing",u);
            return ResponseEntity.status(201).body(Map.of("driverId",
        id));
    }
    @PostMapping("/documents")ResponseEntity<Map<String,UUID>>doc(@RequestParam String type,@RequestParam MultipartFile file)throws IOException{
        UUID d=db.queryForObject("select id from drivers where user_id=?",UUID.class,CurrentUser.id());
        StoredFile s=fs.store(file.getInputStream(),file.getOriginalFilename(),file.getContentType(),file.getSize());
        UUID id=UUID.randomUUID();
        db.update("insert into driver_documents(id,driver_id,type,storage_key,original_filename,content_type) values (?,?,?,?,?,?)",id,d,type,s.storageKey(),s.originalFilename(),s.contentType());
        db.update("update drivers set kyc_status='SUBMITTED' where id=?",d);
            return ResponseEntity.status(201).body(Map.of("documentId",
        id));
    }
}
