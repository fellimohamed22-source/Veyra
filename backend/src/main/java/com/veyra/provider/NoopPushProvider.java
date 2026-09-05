package com.veyra.provider;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.UUID;

@Component
@ConditionalOnProperty(name="veyra.firebase.enabled",havingValue="false",matchIfMissing=true)
public class NoopPushProvider implements PushProvider {
  @Override
  public boolean send(UUID userId,String templateCode,Map<String,Object> data){
    return false;
  }
}
