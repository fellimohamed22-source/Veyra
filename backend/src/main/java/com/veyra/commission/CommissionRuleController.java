package com.veyra.commission;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.veyra.commission.CommissionEngine.*;
import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.OffsetDateTime;
import java.util.*;

/**
 * ADM-COM-01..04: commission rules configurable without deployment
 * (DEC-02/03). Rules are immutable versions; a new rule for the same
 * scope/subject supersedes the open-ended one from its effective date.
 * Every change is audited with actor, before/after and justification.
 */
@RestController
@RequestMapping("/api/v1/admin/commission-rules")
@PreAuthorize("hasAnyRole('ADMIN','FINANCE')")
public class CommissionRuleController {
  private static final ObjectMapper JSON=new ObjectMapper().findAndRegisterModules();
  private final JdbcTemplate db;
  private final CommissionEngine engine;

  public CommissionRuleController(JdbcTemplate db){
    this.db=db;
    this.engine=new CommissionEngine(db);
  }

  public record NewRule(
      @NotBlank @Pattern(regexp="STANDARD|PROFILE|PARTNER_CATEGORY|PARTNER|USER") String scopeType,
      @Pattern(regexp="CLIENT|PARTNER") String profileType,
      @Pattern(regexp="[A-Z_]{2,40}") String partnerCategory,
      UUID partnerId,
      UUID userId,
      @Min(0) @Max(10000) int rateBps,
      @Min(0) Long fixedMinor,
      @Min(0) Long minCommissionMinor,
      @Min(0) Long maxCommissionMinor,
      OffsetDateTime effectiveFrom,
      OffsetDateTime effectiveTo,
      @NotBlank @Size(max=500) String justification){}

  public record Simulation(
      @NotBlank @Pattern(regexp="CLIENT|PARTNER") String bookerType,
      UUID userId,
      UUID partnerId,
      @Min(1) long driverPriceMinor){}

  @GetMapping
  public List<Map<String,Object>> list(@RequestParam(defaultValue="false") boolean activeOnly){
    return db.queryForList(
        "select cp.id,cp.scope_type,cp.profile_type,cp.partner_category,cp.partner_id,po.name as partner_name,cp.user_id," +
        "u.email::text as user_email,cp.commission_bps,cp.fixed_minor,cp.min_commission_minor,cp.max_commission_minor,cp.currency," +
        "cp.version_no,cp.status,cp.effective_from,cp.effective_to,cp.justification,cp.created_by,cp.created_at " +
        "from commission_policy_versions cp left join partner_organizations po on po.id=cp.partner_id left join users u on u.id=cp.user_id " +
        (activeOnly?"where cp.status='ACTIVE' and (cp.effective_to is null or cp.effective_to>now()) ":"") +
        "order by case cp.scope_type when 'USER' then 0 when 'PARTNER' then 1 when 'PARTNER_CATEGORY' then 2 when 'PROFILE' then 3 else 4 end," +
        "cp.effective_from desc nulls last,cp.version_no desc limit 500");
  }

  @PostMapping
  @Transactional
  public ResponseEntity<Map<String,Object>> create(@Valid @RequestBody NewRule r){
    validateSubject(r);
    long fixed=r.fixedMinor()==null?0:r.fixedMinor();
    if(r.minCommissionMinor()!=null&&r.maxCommissionMinor()!=null&&r.minCommissionMinor()>r.maxCommissionMinor())
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"COMMISSION_BOUNDS_INVALID");
    OffsetDateTime from=r.effectiveFrom()==null?OffsetDateTime.now():r.effectiveFrom();
    if(r.effectiveTo()!=null&&!r.effectiveTo().isAfter(from))
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"COMMISSION_PERIOD_INVALID");

    String subject=subjectSql();
    Object[] subjectArgs=subjectArgs(r);
    // Serialize concurrent edits of the same scope/subject.
    db.queryForList("select pg_advisory_xact_lock(hashtextextended(?,0))","commission:"+r.scopeType()+":"+Arrays.toString(subjectArgs));

    List<Map<String,Object>> overlapping=db.queryForList(
        "select id,commission_bps,fixed_minor,min_commission_minor,max_commission_minor,effective_from,effective_to from commission_policy_versions " +
        "where status='ACTIVE' and scope_type=? and "+subject+" and (effective_to is null or effective_to>?) " +
        "and (?::timestamptz is null or effective_from is null or effective_from<?::timestamptz)",
        concat(new Object[]{r.scopeType()},subjectArgs,new Object[]{from,r.effectiveTo(),r.effectiveTo()}));
    List<Map<String,Object>> superseded=new ArrayList<>();
    for(Map<String,Object> o:overlapping){
      OffsetDateTime oFrom=com.veyra.shared.DbTime.toOffsetDateTime(o.get("effective_from"));
      boolean openEndedEarlier=o.get("effective_to")==null&&(oFrom==null||oFrom.isBefore(from));
      // An open-ended earlier version is replaced from the new start date;
      // any other overlap at the same priority is a conflict (COM-04).
      if(!openEndedEarlier)throw new ApiException(HttpStatus.CONFLICT,"COMMISSION_RULE_CONFLICT");
      superseded.add(o);
    }
    for(Map<String,Object> o:superseded)
      db.update("update commission_policy_versions set effective_to=? where id=?",from,o.get("id"));

    Integer version=db.queryForObject(
        "select coalesce(max(version_no),0)+1 from commission_policy_versions where scope_type=? and "+subject,
        Integer.class,concat(new Object[]{r.scopeType()},subjectArgs));
    UUID id=UUID.randomUUID();
    db.update(
        "insert into commission_policy_versions(id,scope_type,profile_type,partner_category,partner_id,user_id,commission_bps,fixed_minor," +
        "min_commission_minor,max_commission_minor,version_no,status,effective_from,effective_to,created_by,justification) " +
        "values (?,?,?,?,?,?,?,?,?,?,?,'ACTIVE',?,?,?,?)",
        id,r.scopeType(),r.profileType(),r.partnerCategory(),r.partnerId(),r.userId(),r.rateBps(),fixed,
        r.minCommissionMinor(),r.maxCommissionMinor(),version,from,r.effectiveTo(),CurrentUser.id(),r.justification().trim());

    Map<String,Object> after=new LinkedHashMap<>();
    after.put("id",id);after.put("scopeType",r.scopeType());after.put("rateBps",r.rateBps());after.put("fixedMinor",fixed);
    after.put("minCommissionMinor",r.minCommissionMinor());after.put("maxCommissionMinor",r.maxCommissionMinor());
    after.put("effectiveFrom",from.toString());after.put("effectiveTo",r.effectiveTo()==null?null:r.effectiveTo().toString());
    audit("COMMISSION_RULE_CREATED",id,superseded,after,r.justification());
    return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("id",id,"versionNo",version,"superseded",superseded.size()));
  }

  public record Deactivation(@NotBlank @Size(max=500) String justification){}

  @PostMapping("/{id}/deactivate")
  @Transactional
  public Map<String,Object> deactivate(@PathVariable UUID id,@Valid @RequestBody Deactivation d){
    List<Map<String,Object>> rows=db.queryForList("select scope_type,status,commission_bps from commission_policy_versions where id=? for update",id);
    if(rows.isEmpty())throw new ApiException(HttpStatus.NOT_FOUND,"NOT_FOUND");
    // The general rule is the last resort of resolution: replace it, never remove it.
    if("STANDARD".equals(rows.getFirst().get("scope_type")))
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"STANDARD_RULE_CANNOT_BE_DEACTIVATED");
    db.update("update commission_policy_versions set status='INACTIVE',effective_to=coalesce(least(effective_to,now()),now()) where id=? and status='ACTIVE'",id);
    audit("COMMISSION_RULE_DEACTIVATED",id,List.of(rows.getFirst()),Map.of("status","INACTIVE"),d.justification());
    return Map.of("id",id,"status","INACTIVE");
  }

  /** Read-only preview: same resolution and arithmetic as offer submission, no mutation. */
  @PostMapping("/simulate")
  public Map<String,Object> simulate(@Valid @RequestBody Simulation s){
    Context ctx;
    if("PARTNER".equals(s.bookerType())){
      if(s.partnerId()==null)throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"PARTNER_REQUIRED");
      List<String> type=db.queryForList("select partner_type from partner_organizations where id=?",String.class,s.partnerId());
      if(type.isEmpty())throw new ApiException(HttpStatus.NOT_FOUND,"PARTNER_NOT_FOUND");
      ctx=Context.partner(s.partnerId(),type.getFirst());
    }else{
      ctx=Context.client(s.userId());
    }
    Rule rule=engine.resolve(ctx);
    long c=CommissionEngine.commission(s.driverPriceMinor(),rule);
    Map<String,Object> result=new LinkedHashMap<>();
    result.put("ruleId",rule.id());
    result.put("scopeType",rule.scopeType());
    result.put("rateBps",rule.rateBps());
    result.put("fixedMinor",rule.fixedMinor());
    result.put("minCommissionMinor",rule.minMinor());
    result.put("maxCommissionMinor",rule.maxMinor());
    result.put("driverPriceMinor",s.driverPriceMinor());
    result.put("commissionMinor",c);
    result.put("customerTotalMinor",Math.addExact(s.driverPriceMinor(),c));
    result.put("driverNetMinor",s.driverPriceMinor());
    return result;
  }

  static void validateSubject(NewRule r){
    boolean ok=switch(r.scopeType()){
      case "STANDARD"->r.profileType()==null&&r.partnerCategory()==null&&r.partnerId()==null&&r.userId()==null;
      case "PROFILE"->r.profileType()!=null&&r.partnerCategory()==null&&r.partnerId()==null&&r.userId()==null;
      case "PARTNER_CATEGORY"->r.partnerCategory()!=null&&r.profileType()==null&&r.partnerId()==null&&r.userId()==null;
      case "PARTNER"->r.partnerId()!=null&&r.profileType()==null&&r.partnerCategory()==null&&r.userId()==null;
      case "USER"->r.userId()!=null&&r.profileType()==null&&r.partnerCategory()==null&&r.partnerId()==null;
      default->false;
    };
    if(!ok)throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"COMMISSION_SCOPE_SUBJECT_MISMATCH");
  }

  /** Null-safe equality on every subject column, so one SQL fits all scopes. */
  static String subjectSql(){
    return "profile_type is not distinct from ? and partner_category is not distinct from ? " +
        "and partner_id is not distinct from ? and user_id is not distinct from ?";
  }

  static Object[] subjectArgs(NewRule r){
    return new Object[]{r.profileType(),r.partnerCategory(),r.partnerId(),r.userId()};
  }

  private static Object[] concat(Object[]...parts){
    List<Object> all=new ArrayList<>();
    for(Object[] p:parts)all.addAll(Arrays.asList(p));
    return all.toArray();
  }

  private void audit(String action,UUID id,Object before,Object after,String justification){
    Map<String,Object> meta=new LinkedHashMap<>();
    meta.put("before",before);
    meta.put("after",after);
    meta.put("justification",justification);
    String json;
    try{json=JSON.writeValueAsString(meta);}catch(Exception e){json="{}";}
    db.update("insert into audit_logs(actor_id,actor_type,action,entity_type,entity_id,metadata) values (?,'ADMIN',?,'COMMISSION_RULE',?,?::jsonb)",
        CurrentUser.id(),action,id,json);
  }
}
