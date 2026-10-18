package com.veyra.booking;

import com.veyra.shared.ApiException;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

/** Message to the client with an offer: optional, short, no contact details (CL-15). */
class OfferMessageTest {
  @Test
  void blankMessagesAreDropped() {
    assertNull(BookingController.offerMessage(null));
    assertNull(BookingController.offerMessage("   "));
  }

  @Test
  void aNormalMessageIsKeptTrimmed() {
    assertEquals("Je serai à l'heure, véhicule climatisé.", BookingController.offerMessage("  Je serai à l'heure, véhicule climatisé.  "));
    // Times and prices are not contact details.
    assertEquals("Départ 15:30, 2 sièges bébé, 48 €", BookingController.offerMessage("Départ 15:30, 2 sièges bébé, 48 €"));
  }

  @Test
  void phoneNumbersAndEmailsAreRefused() {
    for (String m : new String[]{"Appelez-moi au 06 12 34 56 78", "+33612345678", "06.12.34.56.78", "écrivez à karim.b@gmail.com"}) {
      assertEquals("OFFER_MESSAGE_CONTACT_FORBIDDEN", assertThrows(ApiException.class, () -> BookingController.offerMessage(m)).code(), m);
    }
  }

  @Test
  void longMessagesAreRefused() {
    assertEquals("OFFER_MESSAGE_TOO_LONG", assertThrows(ApiException.class, () -> BookingController.offerMessage("a".repeat(201))).code());
  }
}
