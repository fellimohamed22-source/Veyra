package com.veyra.provider;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.UUID;

@Component
@ConditionalOnProperty(name="veyra.firebase.enabled",havingValue="false",matchIfMissing=true)
public class NoopPushProvider implements PushProvider {
  private static final Logger log=LoggerFactory.getLogger(NoopPushProvider.class);

  public NoopPushProvider(){
    // Real gap fixed here while investigating "push notifications don't
    // work": this provider silently no-ops send() with zero indication
    // anywhere that it's even the one in use. If FIREBASE_ENABLED isn't
    // exactly "true" at runtime (e.g. the credentials-bridging logic in
    // docker-entrypoint.sh never ran because FIREBASE_ADMIN_SDK_JSON was
    // empty/unset on the live deployment), the app falls back to this
    // class instead of FirebasePushProvider with no error, no crash, and
    // (before this log line) no trace anywhere that push is effectively
    // disabled. One clear WARN at startup, not per-call, to avoid log
    // spam on every notification attempt.
    log.warn("PUSH_PROVIDER_NOOP firebase push notifications are disabled -- "+
        "veyra.firebase.enabled is not \"true\". Check FIREBASE_ENABLED and "+
        "FIREBASE_ADMIN_SDK_JSON on the deployment if this is unexpected.");
  }

  @Override
  public boolean send(UUID userId,String templateCode,Map<String,Object> data){
    return false;
  }
}
