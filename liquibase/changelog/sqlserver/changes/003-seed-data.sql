--liquibase formatted sql

-- context:dev => solo se aplica si ejecutas con --contexts=dev (o sin filtro de contexts).
-- En "prod" usarías --contexts=prod y estos datos de prueba no se insertarían.

--changeset lab:003-seed-categories context:dev labels:v1
INSERT INTO categories (name) VALUES (N'Bebidas'), (N'Snacks');
--rollback DELETE FROM categories WHERE name IN (N'Bebidas', N'Snacks');

--changeset lab:003-seed-products context:dev labels:v1
INSERT INTO products (name, price, category_id)
SELECT N'Jugo de naranja', 8.50, id FROM categories WHERE name = N'Bebidas'
UNION ALL
SELECT N'Papas fritas', 4.00, id FROM categories WHERE name = N'Snacks';
--rollback DELETE FROM products WHERE name IN (N'Jugo de naranja', N'Papas fritas');
