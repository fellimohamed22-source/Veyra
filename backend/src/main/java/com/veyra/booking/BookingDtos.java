package com.veyra.booking;
import jakarta.validation.constraints.*;import java.time.*;import java.util.*;
public final class BookingDtos{private BookingDtos(){}
 public record Point(@DecimalMin("-90")@DecimalMax("90")double lat,@DecimalMin("-180")@DecimalMax("180")double lng,@NotBlank String address){}
 public record Create(@NotNull Point pickup,@NotNull Point dropoff,@NotNull OffsetDateTime scheduledAt,@NotNull UUID categoryId,@Pattern(regexp="CASH|ONLINE|PARTNER_INVOICE")String paymentMethod,@Pattern(regexp="CLIENT|GUEST|PARTNER")String payerType,UUID partnerId,String beneficiaryName,String beneficiaryPhone){}
 public record Offer(@Min(1)long amountMinor,@Pattern(regexp="[A-Z]{3}")String currency){}
}