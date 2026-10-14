--liquibase formatted sql

--changeset lab:002-create-products labels:v1
--comment: Productos con FK a categorías
CREATE TABLE products (
    id          INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_products PRIMARY KEY,
    name        NVARCHAR(150)     NOT NULL,
    price       DECIMAL(10,2)     NOT NULL CONSTRAINT ck_products_price CHECK (price >= 0),
    category_id INT               NOT NULL CONSTRAINT fk_products_category REFERENCES categories(id),
    created_at  DATETIME2         NOT NULL CONSTRAINT df_products_created DEFAULT SYSUTCDATETIME()
);
--rollback DROP TABLE products;

--changeset lab:002-idx-products-category labels:v1
CREATE INDEX ix_products_category ON products(category_id);
--rollback DROP INDEX ix_products_category ON products;
