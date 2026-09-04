package com.veyra.document;
import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import com.veyra.storage.FileStorageProvider;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import java.io.*;
import java.util.*;
@RestController
@RequestMapping("/api/v1/documents")
public class DocumentController {
  private final JdbcTemplate db; private final FileStorageProvider storage;
  public DocumentController(JdbcTemplate db,FileStorageProvider storage){this.db=db;this.storage=storage;}

  @GetMapping("/{id}/content")
  public ResponseEntity<byte[]> content(@PathVariable UUID id) throws IOException{
    var rows=db.queryForList("select dd.storage_key,dd.original_filename,dd.content_type,d.user_id from driver_documents dd join drivers d on d.id=dd.driver_id where dd.id=?",id);
    if(rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND,"DOCUMENT_NOT_FOUND");
    var x=rows.getFirst();
    UUID owner=(UUID)x.get("user_id");
    boolean admin=db.queryForObject("select count(*) from user_roles ur join roles r on r.id=ur.role_id where ur.user_id=? and r.code in ('ADMIN','SUPPORT')",Integer.class,CurrentUser.id())>0;
    if(!owner.equals(CurrentUser.id())&&!admin) throw new ApiException(HttpStatus.FORBIDDEN,"FORBIDDEN");
    byte[] bytes=storage.load((String)x.get("storage_key")).readAllBytes();
    return ResponseEntity.ok()
      .contentType(MediaType.parseMediaType((String)x.get("content_type")))
      .header(HttpHeaders.CONTENT_DISPOSITION,"inline; filename="document"")
      .body(bytes);
  }
}
