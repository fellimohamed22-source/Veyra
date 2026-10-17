package com.veyra.pricing;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * DEC-18 suggested driver NET price, computed from the owner's grid and
 * the route. Pure arithmetic in minor units. The range bounds are rounded
 * outwards to whole currency units (low down, high up) for display, as in
 * mock-ups 02/12/13 ("Prix conseillé : 45 € – 60 €").
 */
public final class SuggestedPrice {
  private SuggestedPrice(){}

  public record Grid(long baseMinor,long perKmMinor,long perMinuteMinor,long minimumMinor,int spreadBps){}
  public record Range(long centerMinor,long lowMinor,long highMinor){}

  public static Range compute(Grid g,long distanceMeters,long durationSeconds){
    BigDecimal km=BigDecimal.valueOf(distanceMeters).divide(BigDecimal.valueOf(1000),6,RoundingMode.HALF_UP);
    BigDecimal minutes=BigDecimal.valueOf(durationSeconds).divide(BigDecimal.valueOf(60),6,RoundingMode.HALF_UP);
    long raw=BigDecimal.valueOf(g.baseMinor())
        .add(km.multiply(BigDecimal.valueOf(g.perKmMinor())))
        .add(minutes.multiply(BigDecimal.valueOf(g.perMinuteMinor())))
        .setScale(0,RoundingMode.HALF_UP).longValueExact();
    long center=Math.max(raw,g.minimumMinor());
    BigDecimal spread=BigDecimal.valueOf(center).multiply(BigDecimal.valueOf(g.spreadBps())).divide(BigDecimal.valueOf(10000),6,RoundingMode.HALF_UP);
    long low=floorToUnit(BigDecimal.valueOf(center).subtract(spread));
    long high=ceilToUnit(BigDecimal.valueOf(center).add(spread));
    return new Range(center,Math.max(0,low),high);
  }

  static long floorToUnit(BigDecimal minor){
    return minor.divide(BigDecimal.valueOf(100),0,RoundingMode.FLOOR).multiply(BigDecimal.valueOf(100)).longValueExact();
  }

  static long ceilToUnit(BigDecimal minor){
    return minor.divide(BigDecimal.valueOf(100),0,RoundingMode.CEILING).multiply(BigDecimal.valueOf(100)).longValueExact();
  }
}
