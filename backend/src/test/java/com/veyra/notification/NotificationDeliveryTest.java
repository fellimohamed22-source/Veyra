package com.veyra.notification;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Regression guard for a real bug: this job used to mark every PENDING
 * notification SENT regardless of channel, silently stealing PUSH rows
 * from NotificationDispatcher (the only component that actually sends
 * them). Both the select and the update must exclude the PUSH channel.
 */
@ExtendWith(MockitoExtension.class)
class NotificationDeliveryTest {

  @Mock JdbcTemplate db;

  @Test
  void neverSelectsNorMarksPushNotifications() {
    UUID id = UUID.randomUUID();
    ArgumentCaptor<String> select = ArgumentCaptor.forClass(String.class);
    Map<String, Object> row = Map.of("id", id);
    when(db.queryForList(select.capture())).thenReturn(List.of(row));

    new NotificationDelivery(db).deliverInApp();

    assertTrue(select.getValue().contains("channel<>'PUSH'"),
        "the select must exclude PUSH, those belong to NotificationDispatcher");
    ArgumentCaptor<String> update = ArgumentCaptor.forClass(String.class);
    verify(db).update(update.capture(), eq(id));
    assertTrue(update.getValue().contains("channel<>'PUSH'"),
        "the update must also exclude PUSH, in case a row changes channel between select and update");
  }
}
