package com.veyra.shared;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.*;import org.springframework.web.bind.annotation.*;import java.time.Instant;import java.util.*;
@RestControllerAdvice public class ApiExceptionHandler{
 private static final Logger log=LoggerFactory.getLogger(ApiExceptionHandler.class);
 public record Error(String code,String message,String correlationId,Instant timestamp){}
 @ExceptionHandler(ApiException.class) ResponseEntity<Error> api(ApiException e){return ResponseEntity.status(e.status()).body(new Error(e.code(),e.getMessage(),UUID.randomUUID().toString(),Instant.now()));}
 // Malformed or invalid request bodies and parameters are the caller's error (400), not a 500.
 @ExceptionHandler({org.springframework.web.bind.MethodArgumentNotValidException.class,org.springframework.http.converter.HttpMessageNotReadableException.class,
   org.springframework.web.bind.MissingServletRequestParameterException.class,org.springframework.web.method.annotation.MethodArgumentTypeMismatchException.class,
   org.springframework.web.method.annotation.HandlerMethodValidationException.class})
 ResponseEntity<Error> badRequest(Exception e){return ResponseEntity.status(400).body(new Error("VALIDATION_ERROR","Requete invalide",UUID.randomUUID().toString(),Instant.now()));}
 @ExceptionHandler(Exception.class) ResponseEntity<Error> unexpected(Exception e){
  String correlationId=UUID.randomUUID().toString();
  // Real gap fixed here: this handler "handles" the exception by
  // returning a clean response, which means Spring's own default
  // unhandled-exception logging never fires for it -- without an
  // explicit log line here, an INTERNAL_ERROR was completely invisible
  // anywhere in the logs, however carefully anyone searched. Logged at
  // ERROR with the full stack trace and the same correlationId returned
  // to the client, so a report of "INTERNAL_ERROR (correlationId)" can
  // be grepped for directly.
  log.error("UNHANDLED_EXCEPTION correlationId={}",correlationId,e);
  return ResponseEntity.status(500).body(new Error("INTERNAL_ERROR","Erreur interne",correlationId,Instant.now()));
 }
}