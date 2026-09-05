package com.veyra.shared;

import jakarta.validation.ConstraintViolationException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.*;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingRequestHeaderException;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.*;

@RestControllerAdvice
public class ApiExceptionHandler {
  private static final Logger log=LoggerFactory.getLogger(ApiExceptionHandler.class);

  public record Error(String code,String message,String correlationId,Instant timestamp){}

  @ExceptionHandler(ApiException.class)
  ResponseEntity<Error> api(ApiException exception){
    return response(exception.status(),exception.code(),exception.getMessage());
  }

  @ExceptionHandler({
      MethodArgumentNotValidException.class,
      ConstraintViolationException.class,
      IllegalArgumentException.class
  })
  ResponseEntity<Error> validation(Exception exception){
    return response(HttpStatus.UNPROCESSABLE_ENTITY,"VALIDATION_ERROR","Données invalides");
  }

  @ExceptionHandler(MissingRequestHeaderException.class)
  ResponseEntity<Error> missingHeader(MissingRequestHeaderException exception){
    return response(HttpStatus.BAD_REQUEST,"MISSING_HEADER","En-tête requis manquant");
  }

  @ExceptionHandler(Exception.class)
  ResponseEntity<Error> unexpected(Exception exception){
    String correlationId=UUID.randomUUID().toString();
    log.error("Unhandled API error correlationId={}",correlationId,exception);
    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
        .header("X-Correlation-Id",correlationId)
        .body(new Error("INTERNAL_ERROR","Erreur interne",correlationId,Instant.now()));
  }

  private ResponseEntity<Error> response(HttpStatus status,String code,String message){
    String correlationId=UUID.randomUUID().toString();
    if(status.is5xxServerError()){
      log.error("API error status={} code={} correlationId={}",status.value(),code,correlationId);
    }
    return ResponseEntity.status(status)
        .header("X-Correlation-Id",correlationId)
        .body(new Error(code,message,correlationId,Instant.now()));
  }
}
