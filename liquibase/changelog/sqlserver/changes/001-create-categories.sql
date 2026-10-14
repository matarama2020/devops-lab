--liquibase formatted sql

--changeset lab:001-create-categories labels:v1
--comment: Catálogo de categorías
CREATE TABLE categories (
    id   INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_categories PRIMARY KEY,
    name NVARCHAR(100)     NOT NULL CONSTRAINT uq_categories_name UNIQUE
);
--rollback DROP TABLE categories;
