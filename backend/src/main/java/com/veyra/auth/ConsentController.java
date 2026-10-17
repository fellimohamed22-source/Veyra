package com.veyra.auth;

import com.veyra.security.CurrentUser;
import com.veyra.shared.ApiException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * Lets a signed-in user see and change their consents: social sign-ups
 * (no signup form) accept terms/privacy here, and marketing can be
 * granted or withdrawn at any time. Terms/privacy cannot be "withdrawn"
 * through this endpoint: that is an account deletion request.
 */
@RestController
@RequestMapping("/api/v1/me/consents")
public class ConsentController {
  private final ConsentService consents;

  public ConsentController(ConsentService consents){
    this.consents=consents;
  }

  public record Decision(@NotBlank @Pattern(regexp="TERMS|PRIVACY|MARKETING") String type,@NotNull Boolean granted){}

  @GetMapping
  public Map<String,Object> current(){
    return consents.current(CurrentUser.id());
  }

  @PostMapping
  @Transactional
  public Map<String,Object> decide(@Valid @RequestBody Decision d){
    if(!"MARKETING".equals(d.type())&&!d.granted())
      throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,"MANDATORY_CONSENT_CANNOT_BE_WITHDRAWN");
    consents.record(CurrentUser.id(),d.type(),d.granted(),"ACCOUNT_SETTINGS");
    return consents.current(CurrentUser.id());
  }
}
