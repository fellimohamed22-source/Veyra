package com.veyra.driver;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.time.*;
import java.util.*;

@RestController
@RequestMapping("/api/v1/driver/onboarding")
public class DriverOnboardingController {
  private final JdbcTemplate db;

  public DriverOnboardingController(JdbcTemplate db){ this.db=db; }

  public record Company(String siren,String siret,String legalName){}
  public record Vtc(String registrationNumber,String cardNumber,LocalDate issuedAt,LocalDate expiresAt){}
  public record Vehicle(UUID categoryId,String brand,String model,int year,String plateNumber,String color){}

  @PutMapping("/company")
  public void company(@RequestBody Company company){
    if(company.legalName()==null||company.legalName().isBlank()){
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"INVALID_DRIVER_COMPANY");
    }
    UUID driverId=driver();
    db.update(
        "insert into driver_companies(driver_id,siren,siret,legal_name) values (?,?,?,?) " +
        "on conflict(driver_id) do update set siren=excluded.siren,siret=excluded.siret,legal_name=excluded.legal_name",
        driverId,trim(company.siren()),trim(company.siret()),company.legalName().trim());
  }

  @PutMapping("/vtc")
  public void vtc(@RequestBody Vtc vtc){
    if(vtc.registrationNumber()==null||vtc.registrationNumber().isBlank()||
        vtc.cardNumber()==null||vtc.cardNumber().isBlank()||
        (vtc.issuedAt()!=null&&vtc.expiresAt()!=null&&vtc.expiresAt().isBefore(vtc.issuedAt()))){
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"INVALID_VTC_REGISTRATION");
    }
    UUID driverId=driver();
    db.update(
        "insert into driver_vtc_registrations(driver_id,registration_number,card_number,issued_at,expires_at) " +
        "values (?,?,?,?,?) on conflict(driver_id) do update set registration_number=excluded.registration_number," +
        "card_number=excluded.card_number,issued_at=excluded.issued_at,expires_at=excluded.expires_at",
        driverId,vtc.registrationNumber().trim(),vtc.cardNumber().trim(),vtc.issuedAt(),vtc.expiresAt());
  }

  @PostMapping("/vehicles")
  public Map<String,UUID> vehicle(@RequestBody Vehicle vehicle){
    int maxYear=LocalDate.now().getYear()+1;
    if(vehicle.categoryId()==null||vehicle.brand()==null||vehicle.brand().isBlank()||
        vehicle.model()==null||vehicle.model().isBlank()||vehicle.plateNumber()==null||
        vehicle.plateNumber().isBlank()||vehicle.year()<1990||vehicle.year()>maxYear){
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"INVALID_VEHICLE");
    }
    Integer category=db.queryForObject(
        "select count(*) from vehicle_categories where id=? and active=true",
        Integer.class,vehicle.categoryId());
    if(category==null||category==0){
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"INVALID_VEHICLE_CATEGORY");
    }

    UUID id=UUID.randomUUID();
    db.update(
        "insert into vehicles(id,driver_id,category_id,brand,model,year,plate_number,color) values (?,?,?,?,?,?,?,?)",
        id,driver(),vehicle.categoryId(),vehicle.brand().trim(),vehicle.model().trim(),vehicle.year(),
        vehicle.plateNumber().trim(),trim(vehicle.color()));
    return Map.of("vehicleId",id);
  }

  @GetMapping("/status")
  public Map<String,Object> status(){
    UUID driverId=driver();
    return db.queryForMap(
        "select status,kyc_status,marketplace_enabled,rating from drivers where id=?",
        driverId);
  }

  private UUID driver(){
    List<UUID> rows=db.queryForList(
        "select id from drivers where user_id=?",
        UUID.class,CurrentUser.id());
    if(rows.isEmpty()){
      throw new ApiException(HttpStatus.FORBIDDEN,"DRIVER_PROFILE_REQUIRED");
    }
    return rows.getFirst();
  }

  private String trim(String value){
    return value==null?null:value.trim();
  }
}
