package com.veyra.partner;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.*;

/**
 * Partner team (PART-16, validated portal mock-up): members with their
 * role, e-mail invitations, role change and deactivation. Owner only.
 */
@RestController
@RequestMapping("/api/v1/partner/{partnerId}/team")
public class PartnerTeamController {
  static final Set<String> ROLES = Set.of("PARTNER_OWNER", "PARTNER_STAFF", "PARTNER_FINANCE");

  private final JdbcTemplate db;
  private final ObjectProvider<JavaMailSender> mail;

  public PartnerTeamController(JdbcTemplate d, ObjectProvider<JavaMailSender> mail) {
    db = d;
    this.mail = mail;
  }

  public record Add(UUID userId, String role) {}
  public record Invite(String email, String role) {}
  public record Role(String role) {}

  @GetMapping
  List<Map<String, Object>> list(@PathVariable UUID partnerId) {
    owner(partnerId);
    List<Map<String, Object>> rows = new ArrayList<>(db.queryForList(
        "select pu.id,pu.user_id,pu.partner_role,pu.status,u.email::text as email,u.first_name,u.last_name,false as invitation " +
        "from partner_users pu join users u on u.id=pu.user_id where pu.partner_id=? order by pu.partner_role,u.last_name",
        partnerId));
    rows.addAll(db.queryForList(
        "select id,null as user_id,partner_role,'INVITED' as status,email,null as first_name,null as last_name,true as invitation " +
        "from partner_invitations where partner_id=? and status='PENDING' order by created_at",
        partnerId));
    return rows;
  }

  /** Kept for existing clients: attach a known user id directly. */
  @PostMapping
  void add(@PathVariable UUID partnerId, @RequestBody Add a) {
    owner(partnerId);
    role(a.role());
    attach(partnerId, a.userId(), a.role());
  }

  @PostMapping("/invitations")
  @Transactional
  Map<String, Object> invite(@PathVariable UUID partnerId, @RequestBody Invite i) {
    owner(partnerId);
    String role = role(i.role());
    String email = i.email() == null ? "" : i.email().trim().toLowerCase(Locale.ROOT);
    if (!email.matches("[^\\s@]+@[^\\s@]+\\.[^\\s@]+") || email.length() > 254) throw new ApiException(HttpStatus.BAD_REQUEST, "EMAIL_INVALID");
    List<UUID> users = db.queryForList("select id from users where lower(email::text)=? and account_type='CLIENT'", UUID.class, email);
    if (!users.isEmpty()) {
      attach(partnerId, users.getFirst(), role);
      return Map.of("status", "ACTIVE");
    }
    db.update("insert into partner_invitations(partner_id,email,partner_role,invited_by) values (?,?,?,?) " +
        "on conflict (partner_id, lower(email)) where status='PENDING' do update set partner_role=excluded.partner_role",
        partnerId, email, role, CurrentUser.id());
    notify(partnerId, email);
    return Map.of("status", "INVITED");
  }

  @PatchMapping("/{memberId}")
  void changeRole(@PathVariable UUID partnerId, @PathVariable UUID memberId, @RequestBody Role r) {
    owner(partnerId);
    String role = role(r.role());
    guardSelf(partnerId, memberId);
    if (db.update("update partner_users set partner_role=? where id=? and partner_id=?", role, memberId, partnerId) == 0)
      throw new ApiException(HttpStatus.NOT_FOUND, "MEMBER_NOT_FOUND");
  }

  @DeleteMapping("/{memberId}")
  void deactivate(@PathVariable UUID partnerId, @PathVariable UUID memberId) {
    owner(partnerId);
    if (db.update("update partner_invitations set status='REVOKED' where id=? and partner_id=? and status='PENDING'", memberId, partnerId) > 0) return;
    guardSelf(partnerId, memberId);
    if (db.update("update partner_users set status='INACTIVE' where id=? and partner_id=?", memberId, partnerId) == 0)
      throw new ApiException(HttpStatus.NOT_FOUND, "MEMBER_NOT_FOUND");
  }

  /**
   * Applies the pending invitations of the caller's e-mail (first sign-in
   * after being invited). Called when the partner portal loads.
   */
  static void claimInvitations(JdbcTemplate db, UUID userId) {
    List<Map<String, Object>> pending = db.queryForList(
        "select pi.id,pi.partner_id,pi.partner_role from partner_invitations pi join users u on lower(u.email::text)=lower(pi.email) " +
        "where u.id=? and pi.status='PENDING'", userId);
    for (Map<String, Object> p : pending) {
      attach(db, (UUID) p.get("partner_id"), userId, (String) p.get("partner_role"));
      db.update("update partner_invitations set status='ACCEPTED',accepted_at=now() where id=?", p.get("id"));
    }
  }

  private void attach(UUID partnerId, UUID userId, String role) { attach(db, partnerId, userId, role); }

  private static void attach(JdbcTemplate db, UUID partnerId, UUID userId, String role) {
    db.update("insert into partner_users(partner_id,user_id,partner_role) values (?,?,?) on conflict(partner_id,user_id) do update set partner_role=excluded.partner_role,status='ACTIVE'",
        partnerId, userId, role);
    db.update("insert into user_roles(user_id,role_id) select ?,id from roles where code=? on conflict do nothing", userId, role);
  }

  private void notify(UUID partnerId, String email) {
    JavaMailSender sender = mail.getIfAvailable();
    if (sender == null) return;
    try {
      String name = db.queryForObject("select name from partner_organizations where id=?", String.class, partnerId);
      SimpleMailMessage m = new SimpleMailMessage();
      m.setTo(email);
      m.setSubject("Invitation VEYRA — " + name);
      m.setText("Vous avez été invité à rejoindre l'équipe de " + name + " sur VEYRA.\n\n" +
          "Créez votre compte (ou connectez-vous) avec cette adresse e-mail : l'invitation sera appliquée automatiquement.");
      sender.send(m);
    } catch (RuntimeException ignored) {
      // The invitation stays valid even if the e-mail could not be sent.
    }
  }

  private String role(String role) {
    if (role == null || !ROLES.contains(role)) throw new ApiException(HttpStatus.BAD_REQUEST, "PARTNER_ROLE_INVALID");
    return role;
  }

  /** An owner cannot demote or deactivate themselves (the organisation keeps an owner). */
  private void guardSelf(UUID partnerId, UUID memberId) {
    Integer self = db.queryForObject("select count(*) from partner_users where id=? and partner_id=? and user_id=?", Integer.class, memberId, partnerId, CurrentUser.id());
    if (self != null && self > 0) throw new ApiException(HttpStatus.CONFLICT, "CANNOT_CHANGE_OWN_MEMBERSHIP");
  }

  private void owner(UUID p) {
    Integer n = db.queryForObject("select count(*) from partner_users where partner_id=? and user_id=? and partner_role='PARTNER_OWNER' and status='ACTIVE'", Integer.class, p, CurrentUser.id());
    if (n == null || n == 0) throw new org.springframework.security.access.AccessDeniedException("owner");
  }
}
