package com.veyra.auth;
import jakarta.persistence.*;
import java.time.*;
import java.util.*;
@Entity @Table(name="users") public class User{
    @Id @GeneratedValue(strategy=GenerationType.UUID) private UUID id;
    @Column(name="first_name",nullable=false)private String firstName;
    @Column(name="last_name")private String lastName;
    @Column(nullable=false,columnDefinition="citext")private String email;
    /** CLIENT (client app, web portals) or DRIVER (driver app); e-mail is unique per type. */
    @Column(name="account_type",nullable=false)private String accountType="CLIENT";
    @Column(name="password_hash",nullable=false)private String passwordHash;
    @Column(nullable=false)private String status="ACTIVE";
    @Column(name="failed_login_attempts",nullable=false)private int failedLoginAttempts;
    @Column(name="locked_until")private OffsetDateTime lockedUntil;
    protected User(){
    }
    public User(String f,String l,String e,String p){
        this(f,l,e,p,"CLIENT");
    }
    public User(String f,String l,String e,String p,String type){
        firstName=f;
        lastName=l;
        email=e;
        passwordHash=p;
        accountType=type;
    }
    public String accountType(){
        return accountType;
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
