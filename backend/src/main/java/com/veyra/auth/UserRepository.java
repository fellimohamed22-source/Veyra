package com.veyra.auth;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;
public interface UserRepository extends JpaRepository<User,UUID>{
  /** E-mail is unique per account type (CLIENT / DRIVER), see V058. */
  Optional<User> findByEmailIgnoreCaseAndAccountType(String e,String accountType);
  boolean existsByEmailIgnoreCaseAndAccountType(String e,String accountType);
}
