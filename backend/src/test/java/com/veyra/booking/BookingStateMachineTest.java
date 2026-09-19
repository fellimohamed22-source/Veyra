package com.veyra.booking;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class BookingStateMachineTest {
  private final BookingStateMachine machine = new BookingStateMachine();

  @Test
  void canonicalRideJourneyIsAllowed() {
    assertDoesNotThrow(() -> machine.check(BookingStatus.OPEN_FOR_OFFERS, BookingStatus.OFFERS_RECEIVED));
    assertDoesNotThrow(() -> machine.check(BookingStatus.OFFERS_RECEIVED, BookingStatus.CONFIRMED));
    assertDoesNotThrow(() -> machine.check(BookingStatus.CONFIRMED, BookingStatus.DRIVER_EN_ROUTE));
    assertDoesNotThrow(() -> machine.check(BookingStatus.DRIVER_EN_ROUTE, BookingStatus.DRIVER_ARRIVED));
    assertDoesNotThrow(() -> machine.check(BookingStatus.DRIVER_ARRIVED, BookingStatus.IN_PROGRESS));
    assertDoesNotThrow(() -> machine.check(BookingStatus.IN_PROGRESS, BookingStatus.COMPLETED));
    assertDoesNotThrow(() -> machine.check(BookingStatus.COMPLETED, BookingStatus.CLOSED));
  }

  @Test
  void cannotSkipOperationalSteps() {
    assertThrows(IllegalStateException.class, () -> machine.check(BookingStatus.CONFIRMED, BookingStatus.IN_PROGRESS));
    assertThrows(IllegalStateException.class, () -> machine.check(BookingStatus.DRIVER_EN_ROUTE, BookingStatus.IN_PROGRESS));
    assertThrows(IllegalStateException.class, () -> machine.check(BookingStatus.DRIVER_ARRIVED, BookingStatus.COMPLETED));
    assertThrows(IllegalStateException.class, () -> machine.check(BookingStatus.OPEN_FOR_OFFERS, BookingStatus.IN_PROGRESS));
  }

  @Test
  void terminalStatesCannotReopenSilently() {
    for (BookingStatus terminal : new BookingStatus[]{
        BookingStatus.CLOSED, BookingStatus.CANCELLED, BookingStatus.EXPIRED, BookingStatus.NO_OFFER}) {
      assertThrows(IllegalStateException.class, () -> machine.check(terminal, BookingStatus.OPEN_FOR_OFFERS));
      assertThrows(IllegalStateException.class, () -> machine.check(terminal, BookingStatus.CONFIRMED));
    }
  }

  @Test
  void documentedRecoveryTransitionsRemainAllowed() {
    assertDoesNotThrow(() -> machine.check(BookingStatus.DRIVER_CANCELLED, BookingStatus.OPEN_FOR_OFFERS));
    assertDoesNotThrow(() -> machine.check(BookingStatus.CUSTOMER_NO_SHOW, BookingStatus.CLOSED));
    assertDoesNotThrow(() -> machine.check(BookingStatus.INCIDENT, BookingStatus.CLOSED));
  }
}
