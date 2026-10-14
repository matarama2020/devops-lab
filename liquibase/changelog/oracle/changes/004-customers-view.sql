--liquibase formatted sql

-- runOnChange:true => si editas la vista, Liquibase la vuelve a aplicar
-- (válido para objetos "reemplazables": vistas, procedimientos, paquetes).

--changeset lab:004-v-customers labels:v2 runOnChange:true
CREATE OR REPLACE VIEW V_CUSTOMERS AS
SELECT ID,
       DOC_NUMBER,
       UPPER(FULL_NAME) AS FULL_NAME,
       TRUNC(CREATED_AT) AS CREATED_DAY
  FROM CUSTOMERS;
--rollback DROP VIEW V_CUSTOMERS;
