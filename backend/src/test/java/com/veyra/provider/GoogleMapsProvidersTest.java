package com.veyra.provider;

import org.junit.jupiter.api.Test;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class GoogleMapsProvidersTest {

  @Test void decodesGooglesReferencePolyline(){
    // Example from Google's "Encoded Polyline Algorithm Format" documentation.
    var points=GoogleMapsProviders.decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@");
    assertEquals(3,points.size());
    assertEquals(38.5,points.get(0).get("lat"),1e-9);
    assertEquals(-120.2,points.get(0).get("lng"),1e-9);
    assertEquals(40.7,points.get(1).get("lat"),1e-9);
    assertEquals(-120.95,points.get(1).get("lng"),1e-9);
    assertEquals(43.252,points.get(2).get("lat"),1e-9);
    assertEquals(-126.453,points.get(2).get("lng"),1e-9);
  }

  @Test void parsesRoutesApiDistanceDurationAndGeometry(){
    Map<String,Object> response=Map.of("routes",List.of(Map.of(
        "distanceMeters",32150,"duration","2712s","polyline",Map.of("encodedPolyline","_p~iF~ps|U_ulLnnqC"))));
    var route=GoogleMapsProviders.parseRoute(response);
    assertEquals(32150,route.distanceMeters());
    assertEquals(2712,route.durationSeconds());
    assertEquals(2,route.points().size());
  }

  @Test void parsesTurnByTurnSteps(){
    Map<String,Object> response=Map.of("routes",List.of(Map.of(
        "distanceMeters",6000,"duration","900s","polyline",Map.of("encodedPolyline","_p~iF~ps|U_ulLnnqC"),
        "legs",List.of(Map.of("steps",List.of(
            Map.of("distanceMeters",200,"navigationInstruction",Map.of("maneuver","TURN_RIGHT","instructions","Tournez à droite sur Rue de la Paix"),
                "startLocation",Map.of("latLng",Map.of("latitude",48.869,"longitude",2.331))),
            Map.of("distanceMeters",5800,"navigationInstruction",Map.of("maneuver","STRAIGHT","instructions","Continuez sur A1"))))))));
    var steps=GoogleMapsProviders.parseRoute(response).steps();
    assertEquals(2,steps.size());
    assertEquals("TURN_RIGHT",steps.get(0).get("maneuver"));
    assertEquals("Tournez à droite sur Rue de la Paix",steps.get(0).get("instruction"));
    assertEquals(200,steps.get(0).get("distanceMeters"));
    assertEquals(48.869,(Double)steps.get(0).get("lat"),1e-9);
    assertNull(steps.get(1).get("lat"));
  }

  @Test void emptyRoutesIsAnExplicitError(){
    assertThrows(IllegalStateException.class,()->GoogleMapsProviders.parseRoute(Map.of("routes",List.of())));
  }

  @Test void parsesPlacesTextSearchWithNameAndAddress(){
    Map<String,Object> response=Map.of("places",List.of(
        Map.of("id","ChIJ1","formattedAddress","94390 Orly, France","displayName",Map.of("text","Aéroport de Paris-Orly"),"location",Map.of("latitude",48.7262,"longitude",2.3652)),
        Map.of("id","ChIJ2","formattedAddress","Rue de la Paix, 75002 Paris, France","displayName",Map.of("text","Rue de la Paix"),"location",Map.of("latitude",48.869,"longitude",2.331))));
    var places=GoogleMapsProviders.parsePlaces(response);
    assertEquals("Aéroport de Paris-Orly, 94390 Orly",places.get(0).label());
    assertEquals("Rue de la Paix, 75002 Paris",places.get(1).label());
    assertEquals(48.7262,places.get(0).lat(),1e-9);
  }

  @Test void reverseGeocodingUsesTheFirstResult(){
    var p=GoogleMapsProviders.parseReverse(Map.of("results",List.of(Map.of("place_id","p1","formatted_address","1 Rue de Rivoli, 75001 Paris, France"))),48.86,2.34);
    assertEquals("1 Rue de Rivoli, 75001 Paris",p.label());
    assertNull(GoogleMapsProviders.parseReverse(Map.of("results",List.of()),0,0));
  }

  @Test void withoutAKeyTheExistingProvidersKeepServing(){
    LocationIqGeocodingProvider locationIq=mock(LocationIqGeocodingProvider.class);
    OsrmRoutingProvider osrm=mock(OsrmRoutingProvider.class);
    new GoogleMapsProviders.Geocoding(locationIq,"").search("rue de la paix",48.8,2.3);
    verify(locationIq).search("rue de la paix",48.8,2.3);
    new GoogleMapsProviders.Routing(osrm," ").route(48.8,2.3,48.7,2.4);
    verify(osrm).route(48.8,2.3,48.7,2.4);
  }
}
