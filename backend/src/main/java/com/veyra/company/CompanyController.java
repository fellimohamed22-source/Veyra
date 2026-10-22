package com.veyra.company;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import com.veyra.storage.FileStorageProvider;
import com.veyra.storage.StoredFile;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.security.SecureRandom;
import java.time.LocalDate;
import java.util.*;

/**
 * VTC company portal (validated mock-up DEC-13, SOC-01..10): company
 * profile and VEYRA submission, operating and vehicle documents, fleet,
 * affiliated drivers (invitation code, e-mail invitations, validation,
 * vehicle assignment), document expiries and activity. Active company
 * members only; VEYRA approval stays required for marketplace access.
 */
@RestController
@RequestMapping("/api/v1/company")
public class CompanyController {
  /** Operating documents required before submission (to be confirmed legally, see pack DR-AFF). */
  static final List<String> REQUIRED_COMPANY_DOCUMENTS = List.of("KBIS", "REVTC_CERTIFICATE", "RC_INSURANCE");
  static final Set<String> COMPANY_DOCUMENT_TYPES = Set.of("KBIS", "REVTC_CERTIFICATE", "RC_INSURANCE", "OTHER");
  static final Set<String> VEHICLE_DOCUMENT_TYPES = Set.of("REGISTRATION", "VEHICLE_INSURANCE", "TECHNICAL_INSPECTION");
  /** Expiries shown on the dashboard from this many days ahead. */
  static final int EXPIRY_HORIZON_DAYS = 30;
  private static final String CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  private static final SecureRandom RANDOM = new SecureRandom();

  private final JdbcTemplate db;
  private final FileStorageProvider storage;
  private final ObjectProvider<JavaMailSender> mail;

  public CompanyController(JdbcTemplate db, FileStorageProvider storage, ObjectProvider<JavaMailSender> mail) {
    this.db = db;
    this.storage = storage;
    this.mail = mail;
  }

  public record CompanyForm(String legalName, String siren, String revtcNumber, String address, String contactEmail) {}
  public record VehicleForm(UUID categoryId, String brand, String model, Integer year, String plateNumber, String color, Integer seats, Integer baggageCapacity) {}
  public record Assignment(UUID driverId) {}
  public record Approval(UUID vehicleId) {}
  public record Invite(String email) {}

  // ---------------------------------------------------------------- company

  /** Companies the caller manages (portal context). */
  @GetMapping("/mine")
  public List<Map<String, Object>> mine() {
    return db.queryForList(
        "select c.id,c.legal_name,c.siren,c.revtc_number,c.address,c.contact_email,c.status,c.invite_code,c.rejection_reason_code,m.company_role " +
        "from vtc_companies c join company_members m on m.company_id=c.id where m.user_id=? and m.status='ACTIVE' order by c.created_at",
        CurrentUser.id());
  }

  /** SOC-01/02: responsible account creates the company (draft until submitted). */
  @PostMapping
  @Transactional
  public ResponseEntity<Map<String, Object>> create(@RequestBody CompanyForm f) {
    Clean c = clean(f);
    Integer owned = db.queryForObject("select count(*) from company_members where user_id=? and status='ACTIVE'", Integer.class, CurrentUser.id());
    if (owned != null && owned > 0) throw new ApiException(HttpStatus.CONFLICT, "COMPANY_ALREADY_EXISTS");
    UUID id = UUID.randomUUID();
    try {
      db.update("insert into vtc_companies(id,legal_name,siren,revtc_number,address,contact_email,invite_code,created_by) values (?,?,?,?,?,?,?,?)",
          id, c.legalName, c.siren, c.revtc, c.address, c.email, newCode(c.legalName), CurrentUser.id());
    } catch (DuplicateKeyException e) {
      throw new ApiException(HttpStatus.CONFLICT, "SIREN_ALREADY_REGISTERED");
    }
    db.update("insert into company_members(company_id,user_id,company_role) values (?,?,'COMPANY_OWNER')", id, CurrentUser.id());
    db.update("insert into user_roles(user_id,role_id) select ?,id from roles where code='COMPANY_OWNER' on conflict do nothing", CurrentUser.id());
    return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("id", id));
  }

  @PutMapping("/{id}")
  public Map<String, Object> update(@PathVariable UUID id, @RequestBody CompanyForm f) {
    member(id);
    Clean c = clean(f);
    String status = db.queryForObject("select status from vtc_companies where id=?", String.class, id);
    // Identity is frozen once VEYRA has approved it; the contact details stay editable.
    if ("APPROVED".equals(status) || "SUSPENDED".equals(status)) {
      db.update("update vtc_companies set address=?,contact_email=?,updated_at=now() where id=?", c.address, c.email, id);
    } else {
      try {
        db.update("update vtc_companies set legal_name=?,siren=?,revtc_number=?,address=?,contact_email=?,updated_at=now() where id=?",
            c.legalName, c.siren, c.revtc, c.address, c.email, id);
      } catch (DuplicateKeyException e) {
        throw new ApiException(HttpStatus.CONFLICT, "SIREN_ALREADY_REGISTERED");
      }
    }
    return Map.of("id", id);
  }

  /** SOC-07 dashboard: identity, counters, missing items for submission. */
  @GetMapping("/{id}")
  public Map<String, Object> overview(@PathVariable UUID id) {
    member(id);
    Map<String, Object> out = new LinkedHashMap<>(db.queryForMap(
        "select id,legal_name,siren,revtc_number,address,contact_email,status,invite_code,rejection_reason_code,vat_registered,vat_number from vtc_companies where id=?", id));
    out.put("approvedVehicles", count("select count(*) from vehicles v where v.company_id=? and v.status='APPROVED'", id));
    out.put("vehicles", count("select count(*) from vehicles v where v.company_id=?", id));
    out.put("activeDrivers", count("select count(*) from company_affiliations where company_id=? and status='ACTIVE'", id));
    out.put("pendingDrivers", count("select count(*) from company_affiliations where company_id=? and status='PENDING'", id));
    out.put("documentsToRenew", expiries(id).size());
    out.put("ridesThisMonth", count(
        "select count(*) from scheduled_bookings sb join company_affiliations a on a.driver_id=sb.selected_driver_id and a.company_id=? and a.status='ACTIVE' " +
        "where sb.status in ('COMPLETED','CLOSED') and sb.scheduled_at>=date_trunc('month', now() at time zone 'Europe/Paris') at time zone 'Europe/Paris'", id));
    out.put("missing", missing(id));
    return out;
  }

  /** SOC-03: send the dossier to VEYRA (draft or rejected only). */
  @PostMapping("/{id}/submit")
  public ResponseEntity<Map<String, Object>> submit(@PathVariable UUID id) {
    member(id);
    List<String> missing = missing(id);
    if (!missing.isEmpty()) return ResponseEntity.unprocessableEntity().body(Map.of("code", "DOSSIER_INCOMPLETE", "missing", missing));
    int n = db.update("update vtc_companies set status='SUBMITTED',rejection_reason_code=null,updated_at=now() where id=? and status in ('DRAFT','REJECTED')", id);
    if (n == 0) throw new ApiException(HttpStatus.CONFLICT, "COMPANY_NOT_SUBMITTABLE");
    return ResponseEntity.ok(Map.of("status", "SUBMITTED"));
  }

  /** New invitation code (the previous one stops working). */
  @PostMapping("/{id}/invite-code")
  public Map<String, Object> rotateCode(@PathVariable UUID id) {
    member(id);
    String name = db.queryForObject("select legal_name from vtc_companies where id=?", String.class, id);
    String code = newCode(name);
    db.update("update vtc_companies set invite_code=?,updated_at=now() where id=?", code, id);
    return Map.of("inviteCode", code);
  }

  // -------------------------------------------------------------- documents

  @GetMapping("/{id}/documents")
  public List<Map<String, Object>> documents(@PathVariable UUID id) {
    member(id);
    return db.queryForList(
        "select cd.id,cd.type,cd.status,cd.vehicle_id,v.plate_number,v.brand,v.model,cd.original_filename,cd.expires_at,cd.rejection_reason_code,cd.created_at " +
        "from company_documents cd left join vehicles v on v.id=cd.vehicle_id where cd.company_id=? and cd.status<>'SUPERSEDED' order by cd.vehicle_id nulls first,cd.type", id);
  }

  /** SOC-03/04: upload an operating document, or a vehicle document when vehicleId is given. */
  @PostMapping("/{id}/documents")
  public ResponseEntity<Map<String, Object>> upload(@PathVariable UUID id, @RequestParam String type, @RequestParam MultipartFile file,
      @RequestParam(required = false) UUID vehicleId,
      @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate expiresAt) throws IOException {
    member(id);
    String t = type == null ? "" : type.trim().toUpperCase(Locale.ROOT);
    if (vehicleId == null ? !COMPANY_DOCUMENT_TYPES.contains(t) : !VEHICLE_DOCUMENT_TYPES.contains(t))
      throw new ApiException(HttpStatus.BAD_REQUEST, "DOCUMENT_TYPE_INVALID");
    if (vehicleId != null) fleetVehicle(id, vehicleId);
    if (expiresAt != null && expiresAt.isBefore(LocalDate.now())) throw new ApiException(HttpStatus.BAD_REQUEST, "DOCUMENT_EXPIRED");
    if (file == null || file.isEmpty()) throw new ApiException(HttpStatus.BAD_REQUEST, "DOCUMENT_EMPTY");
    StoredFile s = storage.store(file.getInputStream(), file.getOriginalFilename(), file.getContentType(), file.getSize());
    db.update("update company_documents set status='SUPERSEDED' where company_id=? and type=? and vehicle_id is not distinct from ? and status<>'SUPERSEDED'", id, t, vehicleId);
    UUID doc = UUID.randomUUID();
    db.update("insert into company_documents(id,company_id,vehicle_id,type,storage_key,original_filename,content_type,expires_at) values (?,?,?,?,?,?,?,?)",
        doc, id, vehicleId, t, s.storageKey(), s.originalFilename(), s.contentType(), expiresAt);
    // A renewed vehicle document sends the vehicle back to VEYRA review only if it had been refused.
    if (vehicleId != null) db.update("update vehicles set status='PENDING' where id=? and status='REJECTED'", vehicleId);
    return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("documentId", doc));
  }

  /** File of a company document: company members and VEYRA staff only. */
  @GetMapping("/documents/{docId}/content")
  public ResponseEntity<byte[]> content(@PathVariable UUID docId) throws IOException {
    List<Map<String, Object>> rows = db.queryForList("select company_id,storage_key,content_type from company_documents where id=?", docId);
    if (rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "DOCUMENT_NOT_FOUND");
    Map<String, Object> d = rows.getFirst();
    if (!CurrentUser.hasRole("ADMIN") && !CurrentUser.hasRole("SUPPORT")) member((UUID) d.get("company_id"));
    byte[] bytes = storage.load((String) d.get("storage_key")).readAllBytes();
    String type = d.get("content_type") == null ? MediaType.APPLICATION_OCTET_STREAM_VALUE : (String) d.get("content_type");
    return ResponseEntity.ok().contentType(MediaType.parseMediaType(type))
        .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"document\"").body(bytes);
  }

  /** SOC-09: documents expired or expiring soon (company, vehicles, affiliated drivers) and their effect. */
  @GetMapping("/{id}/expiries")
  public List<Map<String, Object>> expiriesList(@PathVariable UUID id) {
    member(id);
    return expiries(id);
  }

  List<Map<String, Object>> expiries(UUID id) {
    return db.queryForList(
        "select * from (" +
        " select cd.id,cd.type,'COMPANY' as scope,null::uuid as vehicle_id,null as subject,cd.expires_at from company_documents cd " +
        "  where cd.company_id=? and cd.vehicle_id is null and cd.status<>'SUPERSEDED' and cd.expires_at<=current_date+? " +
        " union all " +
        " select cd.id,cd.type,'VEHICLE',v.id,v.brand||' '||v.model||' · '||v.plate_number,cd.expires_at from company_documents cd join vehicles v on v.id=cd.vehicle_id " +
        "  where cd.company_id=? and cd.status<>'SUPERSEDED' and cd.expires_at<=current_date+? " +
        " union all " +
        " select dd.id,dd.type,'DRIVER',null::uuid,u.first_name||' '||left(coalesce(u.last_name,''),1)||'.',dd.expires_at from driver_documents dd " +
        "  join company_affiliations a on a.driver_id=dd.driver_id and a.company_id=? and a.status='ACTIVE' join drivers d on d.id=dd.driver_id join users u on u.id=d.user_id " +
        "  where dd.status in ('SUBMITTED','APPROVED') and dd.expires_at<=current_date+? " +
        ") x order by expires_at",
        id, EXPIRY_HORIZON_DAYS, id, EXPIRY_HORIZON_DAYS, id, EXPIRY_HORIZON_DAYS);
  }

  // ---------------------------------------------------------------- vehicles

  @GetMapping("/{id}/vehicles")
  public List<Map<String, Object>> vehicles(@PathVariable UUID id) {
    member(id);
    return db.queryForList(
        "select v.id,v.category_id,vc.display_name as category_name,v.brand,v.model,v.year,v.plate_number,v.color,v.seats,v.baggage_capacity,v.status,v.driver_id," +
        "u.first_name as driver_first_name,u.last_name as driver_last_name," +
        "(select array_agg(cd.type) from company_documents cd where cd.vehicle_id=v.id and cd.status<>'SUPERSEDED') as document_types," +
        "(select min(cd.expires_at) from company_documents cd where cd.vehicle_id=v.id and cd.status<>'SUPERSEDED') as next_expiry " +
        "from vehicles v join vehicle_categories vc on vc.id=v.category_id left join drivers d on d.id=v.driver_id left join users u on u.id=d.user_id " +
        "where v.company_id=? order by v.brand,v.model,v.plate_number", id);
  }

  /** SOC-04: add a fleet vehicle (pending VEYRA approval, unassigned). */
  @PostMapping("/{id}/vehicles")
  public ResponseEntity<Map<String, Object>> addVehicle(@PathVariable UUID id, @RequestBody VehicleForm v) {
    member(id);
    if (v.categoryId() == null || blank(v.brand()) || blank(v.model()) || blank(v.plateNumber()) || v.year() == null)
      throw new ApiException(HttpStatus.BAD_REQUEST, "VEHICLE_INVALID");
    int year = v.year();
    if (year < 1990 || year > LocalDate.now().getYear() + 1) throw new ApiException(HttpStatus.BAD_REQUEST, "VEHICLE_YEAR_INVALID");
    if (v.seats() != null && (v.seats() < 1 || v.seats() > 9)) throw new ApiException(HttpStatus.BAD_REQUEST, "VEHICLE_SEATS_INVALID");
    if (v.baggageCapacity() != null && (v.baggageCapacity() < 0 || v.baggageCapacity() > 20)) throw new ApiException(HttpStatus.BAD_REQUEST, "VEHICLE_BAGGAGE_INVALID");
    String plate = v.plateNumber().trim().toUpperCase(Locale.ROOT).replace(' ', '-');
    if (!plate.matches("[A-Z0-9-]{4,16}")) throw new ApiException(HttpStatus.BAD_REQUEST, "PLATE_INVALID");
    UUID vid = UUID.randomUUID();
    try {
      db.update("insert into vehicles(id,company_id,driver_id,category_id,brand,model,year,plate_number,color,seats,baggage_capacity) values (?,?,null,?,?,?,?,?,?,?,?)",
          vid, id, v.categoryId(), v.brand().trim(), v.model().trim(), year, plate, blank(v.color()) ? null : v.color().trim(), v.seats(), v.baggageCapacity());
    } catch (DuplicateKeyException e) {
      throw new ApiException(HttpStatus.CONFLICT, "PLATE_ALREADY_REGISTERED");
    } catch (org.springframework.dao.DataIntegrityViolationException e) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "VEHICLE_INVALID");
    }
    return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("id", vid));
  }

  /** SOC-08: assign a fleet vehicle to an active affiliated driver, or unassign it (driverId null). */
  @PutMapping("/{id}/vehicles/{vehicleId}/driver")
  @Transactional
  public Map<String, Object> assign(@PathVariable UUID id, @PathVariable UUID vehicleId, @RequestBody Assignment a) {
    member(id);
    fleetVehicle(id, vehicleId);
    if (a.driverId() != null) activeAffiliate(id, a.driverId());
    db.update("update vehicles set driver_id=? where id=? and company_id=?", a.driverId(), vehicleId, id);
    return Map.of("vehicleId", vehicleId, "driverId", a.driverId() == null ? "" : a.driverId());
  }

  // ----------------------------------------------------------------- drivers

  /** SOC-05/06: affiliations with driver identity, VEYRA status, VTC card validity and assigned vehicles. */
  @GetMapping("/{id}/drivers")
  public List<Map<String, Object>> drivers(@PathVariable UUID id) {
    member(id);
    return db.queryForList(
        "select a.id as affiliation_id,a.status,a.requested_at,a.decided_at,d.id as driver_id,u.first_name,u.last_name,d.kyc_status,d.marketplace_enabled," +
        "(select r.expires_at from driver_vtc_registrations r where r.driver_id=d.id) as vtc_expires_at," +
        "(select string_agg(v.brand||' '||v.model||' · '||v.plate_number, ', ') from vehicles v where v.driver_id=d.id and v.company_id=a.company_id) as vehicles " +
        "from company_affiliations a join drivers d on d.id=a.driver_id join users u on u.id=d.user_id " +
        "where a.company_id=? and a.status in ('PENDING','ACTIVE') order by a.status desc,a.requested_at desc", id);
  }

  /** SOC-06/08: validate the attachment and optionally assign a fleet vehicle. */
  @PostMapping("/{id}/drivers/{affiliationId}/approve")
  @Transactional
  public Map<String, Object> approve(@PathVariable UUID id, @PathVariable UUID affiliationId, @RequestBody(required = false) Approval body) {
    member(id);
    UUID driver = affiliation(id, affiliationId, "PENDING");
    db.update("update company_affiliations set status='ACTIVE',decided_at=now(),decided_by=? where id=?", CurrentUser.id(), affiliationId);
    if (body != null && body.vehicleId() != null) {
      fleetVehicle(id, body.vehicleId());
      db.update("update vehicles set driver_id=? where id=? and company_id=?", driver, body.vehicleId(), id);
    }
    return Map.of("status", "ACTIVE");
  }

  @PostMapping("/{id}/drivers/{affiliationId}/reject")
  public Map<String, Object> reject(@PathVariable UUID id, @PathVariable UUID affiliationId) {
    member(id);
    affiliation(id, affiliationId, "PENDING");
    db.update("update company_affiliations set status='REJECTED',decided_at=now(),decided_by=? where id=?", CurrentUser.id(), affiliationId);
    return Map.of("status", "REJECTED");
  }

  /** Ends an active attachment; the company's vehicles are taken back from the driver. */
  @PostMapping("/{id}/drivers/{affiliationId}/end")
  @Transactional
  public Map<String, Object> end(@PathVariable UUID id, @PathVariable UUID affiliationId) {
    member(id);
    UUID driver = affiliation(id, affiliationId, "ACTIVE");
    db.update("update company_affiliations set status='ENDED',decided_at=now(),decided_by=? where id=?", CurrentUser.id(), affiliationId);
    db.update("update vehicles set driver_id=null where company_id=? and driver_id=?", id, driver);
    return Map.of("status", "ENDED");
  }

  @GetMapping("/{id}/invitations")
  public List<Map<String, Object>> invitations(@PathVariable UUID id) {
    member(id);
    return db.queryForList("select id,email,status,created_at from company_invitations where company_id=? and status='PENDING' order by created_at desc", id);
  }

  /** SOC-05: e-mail invitation carrying the company's invitation code. */
  @PostMapping("/{id}/invitations")
  public ResponseEntity<Map<String, Object>> invite(@PathVariable UUID id, @RequestBody Invite i) {
    member(id);
    String email = i.email() == null ? "" : i.email().trim().toLowerCase(Locale.ROOT);
    if (!email.matches("[^\\s@]+@[^\\s@]+\\.[^\\s@]+") || email.length() > 254) throw new ApiException(HttpStatus.BAD_REQUEST, "EMAIL_INVALID");
    db.update("insert into company_invitations(company_id,email,invited_by) values (?,?,?) on conflict (company_id, lower(email)) where status='PENDING' do nothing",
        id, email, CurrentUser.id());
    notify(id, email);
    return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("email", email));
  }

  @DeleteMapping("/{id}/invitations/{invitationId}")
  public Map<String, Object> revoke(@PathVariable UUID id, @PathVariable UUID invitationId) {
    member(id);
    int n = db.update("update company_invitations set status='REVOKED' where id=? and company_id=? and status='PENDING'", invitationId, id);
    if (n == 0) throw new ApiException(HttpStatus.NOT_FOUND, "INVITATION_NOT_FOUND");
    return Map.of("status", "REVOKED");
  }

  // ---------------------------------------------------------------- activity

  /** SOC-10: completed rides of the affiliated drivers this month, with the driver's net price. */
  @GetMapping("/{id}/activity")
  public Map<String, Object> activity(@PathVariable UUID id) {
    member(id);
    String month = "sb.scheduled_at>=date_trunc('month', now() at time zone 'Europe/Paris') at time zone 'Europe/Paris'";
    List<Map<String, Object>> rides = db.queryForList(
        "select sb.id,sb.scheduled_at,sb.status,sb.pickup_address,sb.dropoff_address,u.first_name,u.last_name,bfs.driver_net_amount_minor as driver_price_minor,bfs.currency " +
        "from scheduled_bookings sb join company_affiliations a on a.driver_id=sb.selected_driver_id and a.company_id=? and a.status='ACTIVE' " +
        "join drivers d on d.id=sb.selected_driver_id join users u on u.id=d.user_id " +
        "left join booking_financial_snapshots bfs on bfs.booking_id=sb.id " +
        "where sb.status in ('COMPLETED','CLOSED') and " + month + " order by sb.scheduled_at desc limit 500", id);
    long total = rides.stream().mapToLong(r -> r.get("driver_price_minor") == null ? 0 : ((Number) r.get("driver_price_minor")).longValue()).sum();
    return Map.of("rides", rides, "driverNetTotalMinor", total);
  }

  // ----------------------------------------------------------------- helpers

  /** Active member of the company, or 403. */
  void member(UUID companyId) {
    Integer n = db.queryForObject("select count(*) from company_members where company_id=? and user_id=? and status='ACTIVE'", Integer.class, companyId, CurrentUser.id());
    if (n == null || n == 0) throw new AccessDeniedException("COMPANY_MEMBER_REQUIRED");
  }

  private void fleetVehicle(UUID companyId, UUID vehicleId) {
    Integer n = db.queryForObject("select count(*) from vehicles where id=? and company_id=?", Integer.class, vehicleId, companyId);
    if (n == null || n == 0) throw new ApiException(HttpStatus.NOT_FOUND, "VEHICLE_NOT_FOUND");
  }

  private void activeAffiliate(UUID companyId, UUID driverId) {
    Integer n = db.queryForObject("select count(*) from company_affiliations where company_id=? and driver_id=? and status='ACTIVE'", Integer.class, companyId, driverId);
    if (n == null || n == 0) throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "DRIVER_NOT_AFFILIATED");
  }

  private UUID affiliation(UUID companyId, UUID affiliationId, String status) {
    List<UUID> d = db.queryForList("select driver_id from company_affiliations where id=? and company_id=? and status=? for update", UUID.class, affiliationId, companyId, status);
    if (d.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "AFFILIATION_NOT_FOUND");
    return d.getFirst();
  }

  List<String> missing(UUID id) {
    List<String> missing = new ArrayList<>();
    Map<String, Object> c = db.queryForMap("select revtc_number,address from vtc_companies where id=?", id);
    if (c.get("revtc_number") == null) missing.add("REVTC_NUMBER");
    if (c.get("address") == null) missing.add("ADDRESS");
    Set<String> docs = new HashSet<>(db.queryForList(
        "select distinct type from company_documents where company_id=? and vehicle_id is null and status in ('SUBMITTED','APPROVED')", String.class, id));
    for (String t : REQUIRED_COMPANY_DOCUMENTS) if (!docs.contains(t)) missing.add(t);
    if (count("select count(*) from vehicles where company_id=?", id) == 0) missing.add("VEHICLE");
    return missing;
  }

  private void notify(UUID companyId, String email) {
    JavaMailSender sender = mail.getIfAvailable();
    if (sender == null) return;
    try {
      Map<String, Object> c = db.queryForMap("select legal_name,invite_code from vtc_companies where id=?", companyId);
      SimpleMailMessage m = new SimpleMailMessage();
      m.setTo(email);
      m.setSubject("Invitation VEYRA — " + c.get("legal_name"));
      m.setText(c.get("legal_name") + " vous invite à rejoindre sa flotte sur VEYRA.\n\n" +
          "Dans l'application VEYRA Chauffeur, choisissez « Chauffeur affilié » puis saisissez le code d'invitation : " + c.get("invite_code") + "\n");
      sender.send(m);
    } catch (RuntimeException ignored) {
      // The invitation stays valid even if the e-mail could not be sent.
    }
  }

  static String newCode(String legalName) {
    String letters = legalName == null ? "" : java.text.Normalizer.normalize(legalName, java.text.Normalizer.Form.NFD).replaceAll("[^A-Za-z]", "").toUpperCase(Locale.ROOT);
    String prefix = (letters + "VTRX").substring(0, 4);
    StringBuilder b = new StringBuilder(prefix).append('-');
    for (int i = 0; i < 4; i++) b.append(CODE_ALPHABET.charAt(RANDOM.nextInt(CODE_ALPHABET.length())));
    return b.toString();
  }

  private record Clean(String legalName, String siren, String revtc, String address, String email) {}

  private Clean clean(CompanyForm f) {
    if (f == null || blank(f.legalName())) throw new ApiException(HttpStatus.BAD_REQUEST, "COMPANY_NAME_REQUIRED");
    String siren = f.siren() == null ? "" : f.siren().replaceAll("\\s", "");
    if (!siren.matches("[0-9]{9}") || !luhn(siren)) throw new ApiException(HttpStatus.BAD_REQUEST, "SIREN_INVALID");
    String revtc = blank(f.revtcNumber()) ? null : f.revtcNumber().trim().toUpperCase(Locale.ROOT).replaceAll("\\s", "");
    if (revtc != null && !revtc.matches("[A-Z0-9]{6,32}")) throw new ApiException(HttpStatus.BAD_REQUEST, "REVTC_INVALID");
    String email = blank(f.contactEmail()) ? null : f.contactEmail().trim().toLowerCase(Locale.ROOT);
    if (email != null && (!email.matches("[^\\s@]+@[^\\s@]+\\.[^\\s@]+") || email.length() > 254)) throw new ApiException(HttpStatus.BAD_REQUEST, "EMAIL_INVALID");
    String name = f.legalName().trim();
    if (name.length() > 180) throw new ApiException(HttpStatus.BAD_REQUEST, "COMPANY_NAME_TOO_LONG");
    String address = blank(f.address()) ? null : f.address().trim();
    if (address != null && address.length() > 255) throw new ApiException(HttpStatus.BAD_REQUEST, "ADDRESS_TOO_LONG");
    return new Clean(name, siren, revtc, address, email);
  }

  /** SIREN check digit (Luhn). */
  static boolean luhn(String digits) {
    int sum = 0;
    for (int i = 0; i < digits.length(); i++) {
      int d = digits.charAt(digits.length() - 1 - i) - '0';
      if (i % 2 == 1) { d *= 2; if (d > 9) d -= 9; }
      sum += d;
    }
    return sum % 10 == 0;
  }

  private static boolean blank(String s) { return s == null || s.isBlank(); }

  private long count(String sql, Object... args) {
    Long n = db.queryForObject(sql, Long.class, args);
    return n == null ? 0 : n;
  }
}
