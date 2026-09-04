package com.veyra.reference;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api/v1/reference")
public class ReferenceController {
  private final JdbcTemplate db;

  public ReferenceController(JdbcTemplate db) {
    this.db = db;
  }

  @GetMapping("/vehicle-categories")
  public List<Map<String, Object>> vehicleCategories() {
    return db.queryForList(
        "select id,code,display_name,capacity from vehicle_categories where active=true order by display_name");
  }
}
