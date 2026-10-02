\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE stations (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source              TEXT NOT NULL DEFAULT 'OSINERGMIN',
    source_station_id   TEXT NOT NULL,
    registry_code       TEXT,
    ruc                 TEXT,
    legal_name          TEXT,
    trade_name          TEXT NOT NULL,
    brand               TEXT,
    station_type        TEXT,
    status              TEXT,
    address             TEXT,
    department          TEXT,
    province            TEXT,
    district            TEXT,
    ubigeo               VARCHAR(6),
    latitude            DOUBLE PRECISION,
    longitude           DOUBLE PRECISION,
    location            geometry(Point, 4326),
    phone               TEXT,
    is_formal           BOOLEAN,
    source_updated_at   TIMESTAMPTZ,
    imported_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stations_source_identity_uk UNIQUE (source, source_station_id),
    CONSTRAINT stations_latitude_ck CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT stations_longitude_ck CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    CONSTRAINT stations_ubigeo_ck CHECK (ubigeo IS NULL OR ubigeo ~ '^[0-9]{6}$')
);

CREATE INDEX stations_location_gix ON stations USING GIST (location);
CREATE INDEX stations_ubigeo_idx ON stations (ubigeo);
CREATE INDEX stations_district_idx ON stations (department, province, district);
CREATE INDEX stations_registry_code_idx ON stations (registry_code);

CREATE TABLE fuel_products (
    code                TEXT PRIMARY KEY,
    display_name        TEXT NOT NULL,
    category            TEXT NOT NULL,
    default_unit        TEXT NOT NULL,
    active              BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fuel_products_category_ck
        CHECK (category IN ('GASOLINE', 'DIESEL', 'GLP', 'GNV', 'OTHER'))
);

INSERT INTO fuel_products (code, display_name, category, default_unit) VALUES
    ('REGULAR', 'Gasolina/Gasohol Regular', 'GASOLINE', 'PEN_GALLON'),
    ('PREMIUM', 'Gasolina/Gasohol Premium', 'GASOLINE', 'PEN_GALLON'),
    ('DIESEL_B5', 'Diésel B5', 'DIESEL', 'PEN_GALLON'),
    ('GLP_AUTOMOTOR', 'GLP Automotor', 'GLP', 'PEN_GALLON'),
    ('GNV', 'Gas Natural Vehicular', 'GNV', 'PEN_M3')
ON CONFLICT (code) DO NOTHING;

CREATE TABLE current_fuel_prices (
    station_id          BIGINT NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
    fuel_code           TEXT NOT NULL REFERENCES fuel_products(code),
    price               NUMERIC(12, 4) NOT NULL,
    unit                TEXT NOT NULL,
    currency            CHAR(3) NOT NULL DEFAULT 'PEN',
    reported_at         TIMESTAMPTZ,
    source              TEXT NOT NULL DEFAULT 'OSINERGMIN',
    source_record_id    TEXT,
    imported_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (station_id, fuel_code),
    CONSTRAINT current_fuel_prices_price_ck CHECK (price > 0),
    CONSTRAINT current_fuel_prices_currency_ck CHECK (currency = 'PEN')
);

CREATE INDEX current_fuel_prices_lookup_idx
    ON current_fuel_prices (fuel_code, price);

CREATE TABLE fuel_price_history (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    station_id          BIGINT NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
    fuel_code           TEXT NOT NULL REFERENCES fuel_products(code),
    price               NUMERIC(12, 4) NOT NULL,
    unit                TEXT NOT NULL,
    currency            CHAR(3) NOT NULL DEFAULT 'PEN',
    reported_at         TIMESTAMPTZ,
    source              TEXT NOT NULL DEFAULT 'OSINERGMIN',
    source_record_id    TEXT,
    imported_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fuel_price_history_price_ck CHECK (price > 0),
    CONSTRAINT fuel_price_history_currency_ck CHECK (currency = 'PEN')
);

CREATE INDEX fuel_price_history_station_idx
    ON fuel_price_history (station_id, fuel_code, reported_at DESC);

CREATE INDEX fuel_price_history_imported_idx
    ON fuel_price_history (imported_at DESC);

CREATE TABLE ingestion_runs (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source              TEXT NOT NULL,
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at         TIMESTAMPTZ,
    status              TEXT NOT NULL DEFAULT 'RUNNING',
    records_received    INTEGER NOT NULL DEFAULT 0,
    records_upserted    INTEGER NOT NULL DEFAULT 0,
    records_rejected    INTEGER NOT NULL DEFAULT 0,
    source_reference    TEXT,
    error_summary       TEXT,
    CONSTRAINT ingestion_runs_status_ck
        CHECK (status IN ('RUNNING', 'SUCCEEDED', 'PARTIAL', 'FAILED'))
);

CREATE OR REPLACE FUNCTION set_station_location()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
        NEW.location := ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326);
    ELSE
        NEW.location := NULL;
    END IF;
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER stations_set_location_trg
BEFORE INSERT OR UPDATE OF latitude, longitude, trade_name, address, status
ON stations
FOR EACH ROW
EXECUTE FUNCTION set_station_location();

CREATE VIEW station_current_prices AS
SELECT
    s.id AS station_id,
    s.source_station_id,
    s.registry_code,
    s.trade_name,
    s.brand,
    s.address,
    s.department,
    s.province,
    s.district,
    s.ubigeo,
    s.latitude,
    s.longitude,
    p.fuel_code,
    fp.display_name AS fuel_name,
    p.price,
    p.unit,
    p.currency,
    p.reported_at,
    p.imported_at
FROM stations s
JOIN current_fuel_prices p ON p.station_id = s.id
JOIN fuel_products fp ON fp.code = p.fuel_code;

COMMENT ON VIEW station_current_prices IS
    'Vista de consulta para el bot; los precios deben atribuirse a su fuente oficial y mostrar reported_at.';
