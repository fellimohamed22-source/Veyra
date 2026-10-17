package com.veyra.security;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class PinCryptoTest {
  static final String OLD_KEY="01234567890123456789012345678901";
  static final String NEW_KEY="abcdefghijabcdefghijabcdefghij12";

  @Test void roundtrip(){
    var p=new PinCrypto(OLD_KEY);
    String e=p.encrypt("0427");
    assertNotEquals("0427",e);
    assertEquals("0427",p.decrypt(e));
  }

  @Test void pinsEncryptedBeforeARotationStayReadableThroughThePreviousKey(){
    String beforeRotation=new PinCrypto(OLD_KEY).encrypt("0427");
    var rotated=new PinCrypto(NEW_KEY,OLD_KEY);
    assertEquals("0427",rotated.decrypt(beforeRotation));
    // New PINs use the new key only: unreadable with the old key alone.
    String afterRotation=rotated.encrypt("9135");
    assertEquals("9135",rotated.decrypt(afterRotation));
    assertThrows(IllegalStateException.class,()->new PinCrypto(OLD_KEY).decrypt(afterRotation));
  }

  @Test void withoutThePreviousKeyOldPinsFailCleanly(){
    String beforeRotation=new PinCrypto(OLD_KEY).encrypt("0427");
    var e=assertThrows(IllegalStateException.class,()->new PinCrypto(NEW_KEY).decrypt(beforeRotation));
    assertEquals("PIN_DECRYPTION_FAILED",e.getMessage());
  }
}
