package com.veyra.auth;
import io.jsonwebtoken.*;import io.jsonwebtoken.security.Keys;import org.springframework.beans.factory.annotation.Value;import org.springframework.stereotype.Service;import javax.crypto.SecretKey;import java.nio.charset.StandardCharsets;import java.time.Instant;import java.util.*;
@Service public class JwtService{private final SecretKey key;private final String issuer;private final long ttl;
 public JwtService(@Value("${veyra.jwt.secret}")String s,@Value("${veyra.jwt.issuer}")String i,@Value("${veyra.jwt.access-ttl-minutes}")long t){if(s.getBytes(StandardCharsets.UTF_8).length<32)throw new IllegalArgumentException("JWT secret too short");key=Keys.hmacShaKeyFor(s.getBytes(StandardCharsets.UTF_8));issuer=i;ttl=t;}
 public String issue(UUID id,String email,List<String>roles){Instant n=Instant.now();return Jwts.builder().issuer(issuer).subject(id.toString()).claim("email",email).claim("roles",roles).issuedAt(Date.from(n)).expiration(Date.from(n.plusSeconds(ttl*60))).signWith(key).compact();}
 public UUID userId(String t){return UUID.fromString(Jwts.parser().verifyWith(key).requireIssuer(issuer).build().parseSignedClaims(t).getPayload().getSubject());}
}