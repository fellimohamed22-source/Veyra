FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml .
RUN mvn -B -DskipTests dependency:go-offline
COPY src src
RUN mvn -B -DskipTests package

FROM eclipse-temurin:21-jre
WORKDIR /app
RUN useradd --system --uid 10001 veyra && mkdir -p /app/runtime/documents && chown -R veyra:veyra /app
COPY --from=build /workspace/target/*.jar /app/veyra.jar
USER veyra
EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/veyra.jar"]
