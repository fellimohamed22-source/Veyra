package com.veyra.provider;
import java.util.Map;
import java.util.UUID;
public interface PushProvider {
  boolean send(UUID userId,String templateCode,Map<String,Object> data);
}
