--liquibase formatted sql

-- Cambio "v2": evolución del esquema sobre una tabla con datos.
-- La precondición evita fallar si alguien ya creó la columna a mano (drift).

--changeset lab:004-add-stock labels:v2
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('products') AND name = 'stock'
ALTER TABLE products ADD stock INT NOT NULL CONSTRAINT df_products_stock DEFAULT 0;
--rollback ALTER TABLE products DROP CONSTRAINT df_products_stock;
--rollback ALTER TABLE products DROP COLUMN stock;
