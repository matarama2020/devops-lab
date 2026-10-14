--liquibase formatted sql

-- PL/SQL contiene ';' internos, por eso el changeset usa '/' como delimitador
-- (endDelimiter) y splitStatements:false para que Liquibase no lo trocee.

--changeset lab:002-trg-customers-id labels:v1 endDelimiter:/ splitStatements:false
CREATE OR REPLACE TRIGGER TRG_CUSTOMERS_ID
BEFORE INSERT ON CUSTOMERS
FOR EACH ROW
WHEN (NEW.ID IS NULL)
BEGIN
  SELECT SEQ_CUSTOMERS.NEXTVAL INTO :NEW.ID FROM DUAL;
END;
/
--rollback DROP TRIGGER TRG_CUSTOMERS_ID
