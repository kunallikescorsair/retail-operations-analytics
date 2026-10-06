BEGIN;

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS analytics;

COMMENT ON SCHEMA raw IS
    'Raw source data loaded from external files with minimal transformation.';

COMMENT ON SCHEMA staging IS
    'Cleaned, typed and validated intermediate data models.';

COMMENT ON SCHEMA analytics IS
    'Business-ready dimensional models, facts, dimensions and reporting tables.';

COMMIT;