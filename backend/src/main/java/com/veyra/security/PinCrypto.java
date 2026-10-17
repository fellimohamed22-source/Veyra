package com.veyra.security;
import org.springframework.beans.factory.annotation.Autowired;import org.springframework.beans.factory.annotation.Value;import org.springframework.stereotype.Service;import javax.crypto.*;import javax.crypto.spec.*;import java.nio.charset.StandardCharsets;import java.security.*;import java.util.*;
/**
 * AES-GCM encryption of booking PINs. Supports key rotation: new PINs are
 * always encrypted with the current key (PIN_ENCRYPTION_KEY); PINs of
 * bookings confirmed before a rotation remain readable through
 * PIN_ENCRYPTION_KEY_PREVIOUS until those bookings are over, after which
 * the previous key can be removed.
 */
@Service public class PinCrypto{private final SecretKey key;private final SecretKey previous;private final SecureRandom rnd=new SecureRandom();
 public PinCrypto(String k){this(k,"");}
 @Autowired public PinCrypto(@Value("${veyra.crypto.pin-key}")String k,@Value("${veyra.crypto.pin-key-previous:}")String previousKey){key=aes(k);previous=previousKey==null||previousKey.isBlank()?null:aes(previousKey);}
 private static SecretKey aes(String k){byte[]raw=Arrays.copyOf(k.getBytes(StandardCharsets.UTF_8),32);return new SecretKeySpec(raw,"AES");}
 public String encrypt(String pin){try{byte[]iv=new byte[12];rnd.nextBytes(iv);Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.ENCRYPT_MODE,key,new GCMParameterSpec(128,iv));byte[]e=c.doFinal(pin.getBytes(StandardCharsets.UTF_8));byte[]all=new byte[iv.length+e.length];System.arraycopy(iv,0,all,0,iv.length);System.arraycopy(e,0,all,iv.length,e.length);return Base64.getEncoder().encodeToString(all);}catch(Exception e){throw new IllegalStateException(e);}}
 public String decrypt(String value){try{return decrypt(value,key);}catch(Exception e){if(previous!=null){try{return decrypt(value,previous);}catch(Exception ignored){}}throw new IllegalStateException("PIN_DECRYPTION_FAILED");}}
 private static String decrypt(String value,SecretKey k)throws Exception{byte[]all=Base64.getDecoder().decode(value),iv=Arrays.copyOfRange(all,0,12),e=Arrays.copyOfRange(all,12,all.length);Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,k,new GCMParameterSpec(128,iv));return new String(c.doFinal(e),StandardCharsets.UTF_8);}
}
