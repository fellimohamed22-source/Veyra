package com.veyra.security;
import java.util.UUID;
import org.springframework.security.core.context.SecurityContextHolder;
public final class CurrentUser{
  private CurrentUser(){}
  public static UUID id(){return (UUID)SecurityContextHolder.getContext().getAuthentication().getPrincipal();}
  // Gap trouvé pendant l'audit de ChatController : @PreAuthorize ne
  // permet qu'un contrôle tout-ou-rien au niveau contrôleur, pas un
  // "autorisé si propriétaire OU si ADMIN/SUPPORT" à l'intérieur d'une
  // même méthode métier -- besoin explicite pour le support/litiges
  // (sections 27/72 du prompt). Même convention de rôle que jwtFilter
  // (SimpleGrantedAuthority("ROLE_"+code)).
  public static boolean hasRole(String role){
    return SecurityContextHolder.getContext().getAuthentication().getAuthorities().stream()
        .anyMatch(a->a.getAuthority().equals("ROLE_"+role));
  }
}