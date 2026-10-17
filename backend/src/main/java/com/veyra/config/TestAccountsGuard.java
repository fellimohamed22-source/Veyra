package com.veyra.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Migrations V029/V030/V034 seed test accounts whose passwords are
 * documented in the (public) migration files. Flyway cannot skip an
 * already-applied migration per environment, so production disables
 * them at startup instead: VEYRA_TEST_ACCOUNTS_ENABLED=false suspends
 * the accounts and revokes their sessions. Re-enabling is deliberate
 * (status back to ACTIVE by an admin), never automatic.
 */
@Component
public class TestAccountsGuard implements ApplicationRunner {
  static final List<String> SEEDED_TEST_EMAILS=List.of(
      "client@test.com","chauffeur@test.com",
      "client2@test.com","chauffeur2@test.com",
      "chauffeur3@test.com");

  private final JdbcTemplate db;
  private final boolean enabled;

  public TestAccountsGuard(JdbcTemplate db,@Value("${veyra.test-accounts.enabled:true}") boolean enabled){
    this.db=db;
    this.enabled=enabled;
  }

  @Override
  public void run(ApplicationArguments args){
    if(enabled)return;
    String in=String.join(",",SEEDED_TEST_EMAILS.stream().map(e->"?").toList());
    Object[] emails=SEEDED_TEST_EMAILS.toArray();
    db.update("update user_sessions set revoked_at=now() where revoked_at is null and user_id in (select id from users where email in ("+in+"))",emails);
    db.update("update users set status='SUSPENDED',updated_at=now() where status='ACTIVE' and email in ("+in+")",emails);
  }
}
