package com.veyra.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

@Component
public class BootstrapAdmin implements ApplicationRunner {
  private final JdbcTemplate db;
  private final PasswordEncoder encoder;
  private final String email;
  private final String password;

  public BootstrapAdmin(
      JdbcTemplate db,
      PasswordEncoder encoder,
      @Value("${veyra.bootstrap-admin.email:}") String email,
      @Value("${veyra.bootstrap-admin.password:}") String password) {
    this.db=db;
    this.encoder=encoder;
    this.email=email==null?"":email.trim().toLowerCase();
    this.password=password==null?"":password;
  }

  @Override
  public void run(ApplicationArguments args) {
    if(email.isBlank() || password.isBlank()) return;
    if(password.length()<12) throw new IllegalStateException("Bootstrap admin password must be at least 12 characters");

    var users=db.queryForList("select id from users where email=?", email);
    java.util.UUID userId;
    if(users.isEmpty()){
      userId=java.util.UUID.randomUUID();
      db.update(
        "insert into users(id,first_name,last_name,email,password_hash,status) values (?, 'Veyra', 'Admin', ?, ?, 'ACTIVE')",
        userId,email,encoder.encode(password));
    }else{
      userId=(java.util.UUID)users.getFirst().get("id");
    }

    db.update(
      "insert into user_roles(user_id,role_id) select ?,id from roles where code='ADMIN' on conflict do nothing",
      userId);
  }
}
