package com.veyra.provider;

import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Real UX gap fixed here: addresses were shown as the full raw
 * display_name (every administrative level strung together --
 * arrondissement, department, region, country), when only the street
 * address, city, and postcode are actually wanted in a pickup/dropoff
 * field. shortLabel() builds that shorter form from LocationIQ's own
 * documented addressdetails breakdown.
 */
class LocationIqGeocodingProviderShortLabelTest {

  @Test
  void buildsNumberRoadCityPostcode() {
    Map<String, Object> raw = Map.of(
        "display_name", "Vieux-Port, Quai du Port, Hôtel de Ville, 2nd Arrondissement, Marseille, Bouches-du-Rhône, Provence-Alpes-Côte d'Azur, 13002, France",
        "address", Map.of("house_number", "12", "road", "Quai du Port", "city", "Marseille", "postcode", "13002"));

    assertEquals("12 Quai du Port, Marseille 13002", LocationIqGeocodingProvider.shortLabel(raw));
  }

  @Test
  void omitsHouseNumberWhenAbsent() {
    Map<String, Object> raw = Map.of(
        "display_name", "irrelevant",
        "address", Map.of("road", "Quai du Port", "city", "Marseille", "postcode", "13002"));

    assertEquals("Quai du Port, Marseille 13002", LocationIqGeocodingProvider.shortLabel(raw));
  }

  @Test
  void fallsBackToTownWhenCityIsAbsent() {
    // normalizecity=1 mostly collapses town/village into city, but not
    // guaranteed for every result -- the fallback chain matters.
    Map<String, Object> raw = Map.of(
        "display_name", "irrelevant",
        "address", Map.of("road", "Rue Principale", "town", "Aubagne", "postcode", "13400"));

    assertEquals("Rue Principale, Aubagne 13400", LocationIqGeocodingProvider.shortLabel(raw));
  }

  @Test
  void fallsBackToDisplayNameWhenThereIsNoAddressBreakdownAtAll() {
    // A landmark/POI result or a place outside full OSM coverage --
    // must never show a broken/empty label.
    Map<String, Object> raw = Map.of("display_name", "Château d’If, Marseille, France");

    assertEquals("Château d’If, Marseille, France", LocationIqGeocodingProvider.shortLabel(raw));
  }

  @Test
  void fallsBackToDisplayNameWhenAddressHasNeitherRoadNorCity() {
    Map<String, Object> raw = Map.of(
        "display_name", "France",
        "address", Map.of("country", "France"));

    assertEquals("France", LocationIqGeocodingProvider.shortLabel(raw));
  }
}
