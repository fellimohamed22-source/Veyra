package com.veyra.config;

import org.junit.jupiter.api.Test;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.PropertySource;
import org.springframework.core.io.ClassPathResource;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Production once failed to start because veyra.firebase.credentials-path had
 * slipped under another section (the push provider then saw an empty path).
 * Guards the keys fed by Render environment variables.
 */
class ApplicationYamlTest {
  @Test void environmentBackedKeysSitUnderTheirSection() throws Exception {
    List<PropertySource<?>> sources = new YamlPropertySourceLoader().load("app", new ClassPathResource("application.yml"));
    PropertySource<?> yml = sources.getFirst();
    assertEquals("${FIREBASE_CREDENTIALS_PATH:}", String.valueOf(yml.getProperty("veyra.firebase.credentials-path")));
    assertEquals("${FIREBASE_ENABLED:false}", String.valueOf(yml.getProperty("veyra.firebase.enabled")));
    assertEquals("${VEYRA_TEST_ACCOUNTS_ENABLED:true}", String.valueOf(yml.getProperty("veyra.test-accounts.enabled")));
    assertNull(yml.getProperty("veyra.test-accounts.credentials-path"));
    assertNotNull(yml.getProperty("veyra.jwt.secret"));
    assertNotNull(yml.getProperty("veyra.crypto.pin-key"));
    assertNotNull(yml.getProperty("veyra.stripe.secret-key"));
  }
}
