package com.veyra.booking;
import java.util.*;
public final class BookingStateMachine{
        private static final Map<BookingStatus,Set<BookingStatus>>A=Map.ofEntries(Map.entry(BookingStatus.DRAFT,
        Set.of(BookingStatus.OPEN_FOR_OFFERS,
        BookingStatus.CANCELLED)),Map.entry(BookingStatus.OPEN_FOR_OFFERS,
        Set.of(BookingStatus.OFFERS_RECEIVED,
        BookingStatus.CONFIRMED,
        BookingStatus.CANCELLED,
        BookingStatus.EXPIRED,
        BookingStatus.NO_OFFER)),Map.entry(BookingStatus.OFFERS_RECEIVED,
        Set.of(BookingStatus.CONFIRMED,
        BookingStatus.CANCELLED,
        BookingStatus.EXPIRED)),Map.entry(BookingStatus.CONFIRMED,
        Set.of(BookingStatus.DRIVER_EN_ROUTE,
        BookingStatus.CANCELLED,
        BookingStatus.DRIVER_CANCELLED)),Map.entry(BookingStatus.DRIVER_EN_ROUTE,
        Set.of(BookingStatus.DRIVER_ARRIVED,
        BookingStatus.CANCELLED)),Map.entry(BookingStatus.DRIVER_ARRIVED,
        Set.of(BookingStatus.IN_PROGRESS,
        BookingStatus.CUSTOMER_NO_SHOW)),Map.entry(BookingStatus.IN_PROGRESS,
        Set.of(BookingStatus.COMPLETED,
        BookingStatus.INCIDENT)),Map.entry(BookingStatus.COMPLETED,
        Set.of(BookingStatus.CLOSED)),Map.entry(BookingStatus.DRIVER_CANCELLED,
        Set.of(BookingStatus.OPEN_FOR_OFFERS,
        BookingStatus.CANCELLED)),Map.entry(BookingStatus.CUSTOMER_NO_SHOW,
        Set.of(BookingStatus.CLOSED)),Map.entry(BookingStatus.INCIDENT,
    Set.of(BookingStatus.CLOSED)));
    public void check(BookingStatus f,BookingStatus t){
            if(!A.getOrDefault(f,
        Set.of()).contains(t))throw new IllegalStateException("INVALID_BOOKING_TRANSITION");
    }
}
