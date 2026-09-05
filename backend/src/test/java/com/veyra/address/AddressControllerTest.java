package com.veyra.address;

import com.veyra.provider.GeocodingProvider;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * NominatimGeocodingProvider itself makes real HTTP calls (RestClient
 * built inline, not injected) and isn't unit-testable without hitting
 * real Nominatim -- same real constraint already accepted for
 * StripePaymentService. What's actually testable and worth testing here
 * is AddressController's own contract: never let a missing result fall
 * back to raw coordinates as if they were a real address (redesign
 * principle: an empty reverse-geocode result is a distinct, real
 * outcome the client must handle explicitly, not something to paper
 * over).
 */
@ExtendWith(MockitoExtension.class)
class AddressControllerTest {

  @Mock GeocodingProvider geocoding;

  @Test
  void reverseReturnsFoundFalseRatherThanFabricatingAnAddress() {
    when(geocoding.reverse(43.0, 6.0)).thenReturn(null);

    Map<String, Object> result = new AddressController(geocoding).reverse(43.0, 6.0);

    assertEquals(false, result.get("found"));
    // Nothing else should be present -- specifically no lat/lng echoed
    // back as if they were a resolved address.
    assertNull(result.get("label"));
  }

  @Test
  void reverseReturnsTheRealAddressWhenFound() {
    when(geocoding.reverse(43.2965, 5.3698)).thenReturn(
        new GeocodingProvider.Place("123", "Vieux-Port, Marseille, France", 43.2965, 5.3698));

    Map<String, Object> result = new AddressController(geocoding).reverse(43.2965, 5.3698);

    assertEquals(true, result.get("found"));
    assertEquals("Vieux-Port, Marseille, France", result.get("label"));
  }
}
