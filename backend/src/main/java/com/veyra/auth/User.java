package com.veyra.auth;
import jakarta.persistence.*;
import java.time.*;
import java.util.*;
@Entity @Table(name="users") public class User{
    @Id @GeneratedValue(strategy=GenerationType.UUID) private UUID id;
    @Column(name="first_name",nullable=false)private String firstName;
    @Column(name="last_name")private String lastName;
    @Column(nullable=false,unique=true,columnDefinition="citext")private String email;
    @Column(name="password_hash",nullable=false)private String passwordHash;
    @Column(nullable=false)private String status="ACTIVE";
    @Column(name="failed_login_attempts",nullable=false)private int failedLoginAttempts;
    @Column(name="locked_until")private OffsetDateTime lockedUntil;
    protected User(){
    }
    public User(String f,String l,String e,String p){
        firstName=f;
        lastName=l;
        email=e;
        passwordHash=p;
    }
    public UUID id(){
        return id;
    }
    public String email(){
        return email;
    }
    public String passwordHash(){
        return passwordHash;
    }
    public String status(){
        return status;
    }
    public OffsetDateTime lockedUntil(){
        return lockedUntil;
    }
    public void failed(){
        failedLoginAttempts++;
        if(failedLoginAttempts>=5)lockedUntil=OffsetDateTime.now().plusMinutes(15);
    }
    public void success(){
        failedLoginAttempts=0;
        lockedUntil=null;
    }
}
