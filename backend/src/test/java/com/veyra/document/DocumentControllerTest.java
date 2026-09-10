package com.veyra.document;

import com.veyra.shared.ApiException;
import com.veyra.storage.FileStorageProvider;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.io.ByteArrayInputStream;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * No test existed at all for this controller before, despite it
 * streaming potentially sensitive KYC document bytes (identity card,
 * VTC card, etc.) and gating access with its own authorization check.
 * Note: this controller checks ADMIN/SUPPORT via a direct DB query
 * (user_roles/roles tables) rather than CurrentUser.hasRole() /
 * SecurityContextHolder authorities used elsewhere in this session's
 * fixes -- an inconsistency worth knowing about, but not a bug (a live
 * DB check is, if anything, more paranoid/correct than trusting a
 * possibly-stale JWT claim), so left exactly as written rather than
 * "fixed" without a demonstrated problem.
 */
@ExtendWith(MockitoExtension.class)
class DocumentControllerTest {

  @Mock JdbcTemplate db;
  @Mock FileStorageProvider storage;

  private final UUID documentId = UUID.randomUUID();
  private final UUID ownerId = UUID.randomUUID();

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private DocumentController controller() {
    return new DocumentController(db, storage);
  }

  private void stubDocumentRow() {
    when(db.queryForList(contains("from driver_documents dd join drivers d"), eq(documentId)))
        .thenReturn(List.of(Map.of(
            "storage_key", "some/key.jpg",
            "original_filename", "id.jpg",
            "content_type", "image/jpeg",
            "user_id", ownerId)));
  }

  @Test
  void theOwnerCanReadTheirOwnDocument() throws Exception {
    // Real runtime NPE found via the actual test-execution log the user
    // pasted (backend-ci run on 8e7bc89): DocumentController.content()
    // computes the ADMIN/SUPPORT role check UNCONDITIONALLY, even on the
    // owner-access path where its result ends up unused (a real, minor
    // inefficiency in the controller itself -- an extra DB round-trip
    // even when owner access already succeeds -- but not something to
    // "fix" here without being asked; this test just needs to correctly
    // stub what the controller actually, unconditionally calls).
    // Mockito's default answer for an unstubbed queryForObject(...,
    // Integer.class, ...) is null, and `null > 0` NPEs on unboxing --
    // exactly matching the real stack trace at DocumentController.java:22.
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(ownerId, null));
    stubDocumentRow();
    when(db.queryForObject(contains("from user_roles ur join roles r"), eq(Integer.class), any()))
        .thenReturn(0);
    when(storage.load("some/key.jpg")).thenReturn(new ByteArrayInputStream("bytes".getBytes()));

    ResponseEntity<byte[]> response = controller().content(documentId);

    assertEquals(200, response.getStatusCode().value());
    assertArrayEquals("bytes".getBytes(), response.getBody());
    assertEquals("inline; filename=\"document\"", response.getHeaders().getFirst(HttpHeaders.CONTENT_DISPOSITION));
  }

  @Test
  void someoneUninvolvedAndNonAdminGetsForbidden() throws Exception {
    // Real compile error found via the actual CI log the user pasted
    // (backend-ci run on 84601b1): "unreported exception
    // java.io.IOException; must be caught or declared to be thrown" at
    // the verify(storage, never()).load(...) call below --
    // FileStorageProvider.load() is declared `throws IOException`, and
    // even a Mockito verify() call is, syntactically, a real method
    // call the compiler type-checks against that signature. Missing
    // `throws Exception` here was the exact and only cause of both
    // prior reverts of this file -- confirmed from real log output,
    // not guessed.
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(UUID.randomUUID(), null));
    stubDocumentRow();
    when(db.queryForObject(contains("from user_roles ur join roles r"), eq(Integer.class), any()))
        .thenReturn(0);

    ApiException ex = assertThrows(ApiException.class, () -> controller().content(documentId));

    assertEquals("FORBIDDEN", ex.code());
    verify(storage, never()).load(anyString());
  }

  @Test
  void adminCanReadAnyonesDocumentViaTheDbRoleCheck() throws Exception {
    UUID adminId = UUID.randomUUID();
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(adminId, null));
    stubDocumentRow();
    when(db.queryForObject(contains("from user_roles ur join roles r"), eq(Integer.class), eq(adminId)))
        .thenReturn(1);
    when(storage.load("some/key.jpg")).thenReturn(new ByteArrayInputStream("bytes".getBytes()));

    ResponseEntity<byte[]> response = controller().content(documentId);

    assertEquals(200, response.getStatusCode().value());
  }

  @Test
  void unknownDocumentIdReturns404WithoutEverCheckingRoleOrStorage() {
    SecurityContextHolder.getContext().setAuthentication(new TestingAuthenticationToken(UUID.randomUUID(), null));
    when(db.queryForList(contains("from driver_documents dd join drivers d"), eq(documentId)))
        .thenReturn(List.of());

    ApiException ex = assertThrows(ApiException.class, () -> controller().content(documentId));

    assertEquals("DOCUMENT_NOT_FOUND", ex.code());
    verify(db, never()).queryForObject(contains("from user_roles"), eq(Integer.class), any());
    verifyNoInteractions(storage);
  }
}
