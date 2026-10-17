package com.veyra.provider;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.web.client.RestClient;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

/**
 * DEC-07: SMS through Twilio's Messages API. Inactive (never calls out)
 * until TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_FROM are set.
 * Logs never contain the recipient number nor the message body.
 */
@Component
public class TwilioSmsProvider implements SmsProvider {
  private static final Logger log=LoggerFactory.getLogger(TwilioSmsProvider.class);
  private final String accountSid;
  private final String authToken;
  private final String from;
  private final RestClient http;

  public TwilioSmsProvider(
      @Value("${veyra.twilio.account-sid:}") String accountSid,
      @Value("${veyra.twilio.auth-token:}") String authToken,
      @Value("${veyra.twilio.from:}") String from){
    this.accountSid=accountSid==null?"":accountSid.trim();
    this.authToken=authToken==null?"":authToken.trim();
    this.from=from==null?"":from.trim();
    this.http=RestClient.builder().baseUrl("https://api.twilio.com").build();
  }

  @Override
  public boolean isConfigured(){
    return !accountSid.isEmpty()&&!authToken.isEmpty()&&!from.isEmpty();
  }

  @Override
  public boolean send(String toE164,String body){
    if(!isConfigured())return false;
    var form=new LinkedMultiValueMap<String,String>();
    form.add("To",toE164);
    form.add("Body",body);
    // A Messaging Service SID (MG...) or a sender number/alphanumeric ID.
    form.add(from.startsWith("MG")?"MessagingServiceSid":"From",from);
    String basic=Base64.getEncoder().encodeToString((accountSid+":"+authToken).getBytes(StandardCharsets.UTF_8));
    try{
      http.post().uri("/2010-04-01/Accounts/{sid}/Messages.json",accountSid)
          .header("Authorization","Basic "+basic)
          .contentType(MediaType.APPLICATION_FORM_URLENCODED)
          .body(form)
          .retrieve().toBodilessEntity();
      return true;
    }catch(RuntimeException e){
      log.warn("SMS_SEND_FAILED provider=twilio error={}",e.getClass().getSimpleName());
      return false;
    }
  }
}
