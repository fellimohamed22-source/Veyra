package com.veyra.admin;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * Gap found while auditing DocumentController: GET /{id}/content already
 * worked and correctly authorized ADMIN/SUPPORT or the document owner,
 * but nothing ever exposed which documents exist for a given driver --
 * meaning approveDriver()/rejectDriver() (both immediately below this
 * new endpoint in the real file) were fully callable without staff ever
 * having a way to list, let alone view, the actual submitted documents
 * first. This only covers the new read endpoint; approve/reject
 * themselves are unchanged.
 */
@ExtendWith(MockitoExtension.class)
class AdminControllerDriverDocumentsTest {

  @Mock JdbcTemplate db;

  @Test
  void listsDocumentsScopedToTheRequestedDriverOnly(){
    UUID driverId=UUID.randomUUID();
    when(db.queryForList(contains("from driver_documents where driver_id=?"),eq(driverId)))
        .thenReturn(List.of(Map.of("id",UUID.randomUUID(),"type","VTC_CARD","status","SUBMITTED")));

    List<Map<String,Object>> result=new AdminController(db).driverDocuments(driverId);

    assertEquals(1,result.size());
    verify(db).queryForList(contains("where driver_id=?"),eq(driverId));
  }
}
