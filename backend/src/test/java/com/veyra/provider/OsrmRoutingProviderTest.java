package com.veyra.provider;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class OsrmRoutingProviderTest {

  @Test
  void parsesGeoJsonGeometryInLatLngOrder(){
    RestClient.Builder builder=RestClient.builder();
    MockRestServiceServer server=MockRestServiceServer.bindTo(builder).build();
    OsrmRoutingProvider provider=new OsrmRoutingProvider(builder,"https://router.test");

    server.expect(requestTo(
        "https://router.test/route/v1/driving/5.3698,43.2965;5.2146,43.4389?overview=simplified&geometries=geojson&steps=false"))
      .andRespond(withSuccess(
        """
        {
          "routes":[{
            "distance":26500.4,
            "duration":1800.7,
            "geometry":{
              "type":"LineString",
              "coordinates":[
                [5.3698,43.2965],
                [5.3000,43.3500],
                [5.2146,43.4389]
              ]
            }
          }]
        }
        """,
        MediaType.APPLICATION_JSON));

    RoutingProvider.Route route=provider.route(43.2965,5.3698,43.4389,5.2146);

    assertEquals(26500,route.distanceMeters());
    assertEquals(1800,route.durationSeconds());
    assertEquals(3,route.points().size());
    assertEquals(43.2965,route.points().getFirst().lat(),0.00001);
    assertEquals(5.3698,route.points().getFirst().lng(),0.00001);
    server.verify();
  }
}
