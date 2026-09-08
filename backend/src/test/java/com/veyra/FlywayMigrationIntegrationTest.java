package com.veyra;

import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.output.MigrateResult;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Section 51 (and the earlier prompt's section 24) of the master
 * prompt: "Une compilation Java réussie n'est pas suffisante" pour
 * valider la DB. Chaque autre test de cette suite mocke JdbcTemplate
 * (confirmé en lisant l'ensemble de backend/src/test avant d'écrire
 * celui-ci) -- aucun ne vérifie donc jamais que les 20+ migrations
 * Flyway s'appliquent réellement, dans l'ordre, sur une base
 * PostgreSQL/PostGIS vraiment vide.
 *
 * Volontairement un test Flyway PUR (pas un @SpringBootTest complet) :
 * démarrer tout le contexte Spring exigerait aussi des secrets/config
 * pour Stripe, Firebase, JWT, etc. -- un échec de test masquerait alors
 * potentiellement une vraie régression de migration derrière un simple
 * problème de configuration non lié. Ce test isole précisément ce que
 * la section 51 demande : DB vide → migrate → succès, rien d'autre.
 */
@Testcontainers
class FlywayMigrationIntegrationTest {

  @Container
  static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>(
      DockerImageName.parse("postgis/postgis:16-3.4").asCompatibleSubstituteFor("postgres"));

  @Test
  void everyMigrationAppliesCleanlyToAGenuinelyEmptyDatabase() {
    Flyway flyway = Flyway.configure()
        .dataSource(postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword())
        .locations("classpath:db/migration")
        .load();

    MigrateResult result = flyway.migrate();

    assertTrue(result.success, "Flyway migration failed: " + result.migrations);
    assertFalse(result.migrations.isEmpty(), "no migrations were found/applied at all");
  }

  @Test
  void coreTablesExistAfterMigration() throws Exception {
    Flyway flyway = Flyway.configure()
        .dataSource(postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword())
        .locations("classpath:db/migration")
        .load();
    flyway.migrate();

    try (Connection conn = DriverManager.getConnection(
             postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword());
         Statement stmt = conn.createStatement()) {
      for (String table : new String[]{
          "users", "drivers", "vehicles", "scheduled_bookings", "driver_offers",
          "offer_visibility_policy_versions", "commission_policy_versions",
          "partner_organizations", "partner_beneficiaries", "partner_invoices",
          "notifications", "chat_messages", "ride_ratings"}) {
        try (ResultSet rs = stmt.executeQuery(
            "select count(*) from information_schema.tables where table_name = '" + table + "'")) {
          rs.next();
          assertEquals(1, rs.getInt(1), "table missing after migration: " + table);
        }
      }
    }
  }
}
