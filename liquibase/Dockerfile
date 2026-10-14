# Imagen de Liquibase para el laboratorio.
# - Versión fijada (4.x trae drivers JDBC incluidos; 5.x requiere instalarlos con `lpm`).
# - Oracle 11g: el ojdbc8 que trae Liquibase es de una versión reciente (23.x) que ya no
#   certifica 11g. Lo reemplazamos por ojdbc8 19.x, la última línea que soporta 11.2.
# - Los changelogs se copian dentro: así el Job de Kubernetes no necesita volúmenes.
FROM liquibase/liquibase:4.29.2

USER root
RUN rm -f /liquibase/internal/lib/ojdbc*.jar
ADD --chmod=644 https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc8/19.24.0.0/ojdbc8-19.24.0.0.jar /liquibase/lib/
USER liquibase

COPY --chown=liquibase:liquibase changelog/ /liquibase/changelog/
