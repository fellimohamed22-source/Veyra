package com.veyra.shared;
import org.springframework.http.*;import org.springframework.web.bind.annotation.*;import java.time.Instant;import java.util.*;
@RestControllerAdvice public class ApiExceptionHandler{
 public record Error(String code,String message,String correlationId,Instant timestamp){}
 @ExceptionHandler(ApiException.class) ResponseEntity<Error> api(ApiException e){return ResponseEntity.status(e.status()).body(new Error(e.code(),e.getMessage(),UUID.randomUUID().toString(),Instant.now()));}
 @ExceptionHandler(Exception.class) ResponseEntity<Error> unexpected(Exception e){return ResponseEntity.status(500).body(new Error("INTERNAL_ERROR","Erreur interne",UUID.randomUUID().toString(),Instant.now()));}
}