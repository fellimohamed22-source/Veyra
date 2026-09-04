package com.veyra.shared;
import org.springframework.http.HttpStatus;
public class ApiException extends RuntimeException{private final HttpStatus status;private final String code;public ApiException(HttpStatus s,String c){super(c);status=s;code=c;}public HttpStatus status(){return status;}public String code(){return code;}}