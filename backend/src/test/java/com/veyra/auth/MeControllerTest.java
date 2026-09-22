package com.veyra.auth;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import com.veyra.storage.FileStorageProvider;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * No test existed for this controller at all before. Written after a
 * real bug this exact endpoint hit in production: a real user's phone
 * camera photo exceeded veyra.storage.max-file-size-mb and the app got
 * back an opaque 500 (DioException [bad response], confirmed via the
 * client's own diagnostic banner) instead of a clean, actionable error
 * -- FilesystemStorageProvider.store() throws a plain
 * IllegalArgumentException, which ApiExceptionHandler had no dedicated
 * handler for, so it fell through to the generic 500 path.
 */
@ExtendWith(MockitoExtension.class)
class MeControllerTest {

  @Mock JdbcTemplate db;
  @Mock PasswordEncoder encoder;
  @Mock FileStorageProvider storage;

  private MeController controller() {
    return new MeController(db, encoder, storage);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  private void stubCurrentUser(UUID id) {
    SecurityContext ctx = mock(SecurityContext.class);
    when(ctx.getAuthentication()).thenReturn(
        new UsernamePasswordAuthenticationToken(id, null, java.util.List.of()));
    SecurityContextHolder.setContext(ctx);
  }

  @Test
  void anOversizedAvatarReturnsACleanBadRequestNotAnOpaqueServerError() throws Exception {
    UUID userId = UUID.randomUUID();
    stubCurrentUser(userId);
    MockMultipartFile file = new MockMultipartFile(
        "file", "photo.jpg", "image/jpeg", "not the real bytes, size is what matters here".getBytes());
    // The real storage provider throws IllegalArgumentException for an
    // oversized file -- simulating that exact real-world failure here,
    // not a made-up scenario.
    when(storage.store(any(), any(), eq("image/jpeg"), anyLong()))
        .thenThrow(new IllegalArgumentException("INVALID_FILE_SIZE"));

    ApiException ex = assertThrows(ApiException.class, () -> controller().avatar(file));

    assertEquals(HttpStatus.BAD_REQUEST, ex.status());
    assertEquals("INVALID_FILE_SIZE", ex.code());
    // Confirms the fix actually stops the exception from reaching the
    // database update path at all -- a rejected upload must not
    // silently persist a half-done state.
    verify(db, never()).update(anyString(), any(), any(), any());
  }

  @Test
  void aWrongContentTypeIsRejectedBeforeEverTouchingStorage() {
    UUID userId = UUID.randomUUID();
    stubCurrentUser(userId);
    MockMultipartFile file = new MockMultipartFile(
        "file", "doc.pdf", "application/pdf", "not an image".getBytes());

    ApiException ex = assertThrows(ApiException.class, () -> controller().avatar(file));

    assertEquals(HttpStatus.BAD_REQUEST, ex.status());
    assertEquals("AVATAR_IMAGE_REQUIRED", ex.code());
    verifyNoInteractions(storage);
  }
}
