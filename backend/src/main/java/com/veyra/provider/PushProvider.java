package com.veyra.provider;
import java.util.Map;
import java.util.UUID;
public interface PushProvider {
  default boolean available(){ return true; }
  boolean send(UUID userId,String templateCode,Map<String,Object> data);
}
