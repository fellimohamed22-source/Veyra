# Multi-stage build: compile with the full JDK+Maven image, run on a slim JRE.
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build
COPY pom.xml .
RUN mvn -B dependency:go-offline
COPY src ./src
RUN mvn -B package -DskipTests

FROM eclipse-temurin:21-jre
RUN useradd --system --create-home veyraapp
WORKDIR /app
COPY --from=build /build/target/*.jar app.jar
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh && chown -R veyraapp:veyraapp /app
USER veyraapp
EXPOSE 8080
ENTRYPOINT ["/app/docker-entrypoint.sh"]
