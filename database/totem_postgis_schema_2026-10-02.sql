--
-- PostgreSQL database dump
--

-- Dumped from database version 16.9 (Debian 16.9-1.pgdg110+1)
-- Dumped by pg_dump version 16.9 (Debian 16.9-1.pgdg110+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: fn_freshness_label(text, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_freshness_label(p_source text, p_reported_at timestamp with time zone, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    v_hours NUMERIC;
BEGIN
    IF p_reported_at IS NULL THEN
        RETURN 'Sin fecha';
    END IF;

    IF p_expires_at IS NOT NULL AND NOW() > p_expires_at THEN
        RETURN 'Desactualizado';
    END IF;

    v_hours := EXTRACT(EPOCH FROM (NOW() - p_reported_at)) / 3600.0;

    IF p_source = 'OFFICIAL' THEN
        RETURN 'Oficial · ' || to_char(p_reported_at, 'DD/MM HH24:MI');
    ELSIF p_source IN ('FIELD_VERIFIED','STATION_REPORTED') THEN
        IF v_hours <= 24 THEN RETURN 'Verificado hoy';
        ELSIF v_hours <= 72 THEN RETURN 'Verificado hace ' || floor(v_hours/24)::INT || ' día(s)';
        ELSE RETURN 'Desactualizado';
        END IF;
    ELSIF p_source = 'USER_REPORTED' THEN
        RETURN 'Por confirmar';
    ELSE
        RETURN 'DEMO';
    END IF;
END;
$$;


--
-- Name: FUNCTION fn_freshness_label(p_source text, p_reported_at timestamp with time zone, p_expires_at timestamp with time zone); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_freshness_label(p_source text, p_reported_at timestamp with time zone, p_expires_at timestamp with time zone) IS 'Umbrales tomados de la propuesta TOTEM (72h para campo/estación, DEMO/oficial sin expiración fija). Ajustar aquí después del piloto según la volatilidad real medida por combustible y distrito.';


--
-- Name: set_station_location(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_station_location() RETURNS trigger
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: app_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_events (
    id bigint NOT NULL,
    app_user_id bigint NOT NULL,
    event_name text NOT NULL,
    fuel_code text,
    result_count integer,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT app_events_metadata_object_ck CHECK ((jsonb_typeof(metadata) = 'object'::text)),
    CONSTRAINT app_events_result_count_ck CHECK (((result_count IS NULL) OR (result_count >= 0)))
);


--
-- Name: app_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.app_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.app_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: app_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_users (
    id bigint NOT NULL,
    channel text NOT NULL,
    external_id text NOT NULL,
    last_latitude double precision,
    last_longitude double precision,
    last_location public.geometry(Point,4326),
    last_location_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    pending_flow text,
    CONSTRAINT app_users_channel_check CHECK ((channel = ANY (ARRAY['whatsapp'::text, 'telegram'::text])))
);


--
-- Name: TABLE app_users; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.app_users IS 'Identidad de usuario agnóstica de canal para las tablas nuevas del MVP TOTEM (no reemplaza bot_users de Telegram).';


--
-- Name: app_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.app_users ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.app_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: bot_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bot_events (
    id bigint NOT NULL,
    telegram_chat_id bigint NOT NULL,
    event_name text NOT NULL,
    fuel_code text,
    result_count integer,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT bot_events_metadata_object_ck CHECK ((jsonb_typeof(metadata) = 'object'::text)),
    CONSTRAINT bot_events_result_count_ck CHECK (((result_count IS NULL) OR (result_count >= 0)))
);


--
-- Name: bot_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.bot_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.bot_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: bot_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bot_users (
    telegram_chat_id bigint NOT NULL,
    latitude double precision NOT NULL,
    longitude double precision NOT NULL,
    location public.geometry(Point,4326) NOT NULL,
    location_shared_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT bot_users_latitude_ck CHECK (((latitude >= ('-90'::integer)::double precision) AND (latitude <= (90)::double precision))),
    CONSTRAINT bot_users_longitude_ck CHECK (((longitude >= ('-180'::integer)::double precision) AND (longitude <= (180)::double precision)))
);


--
-- Name: brand_fuel_names; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.brand_fuel_names (
    brand text NOT NULL,
    fuel_code text NOT NULL,
    label text NOT NULL,
    source_type text DEFAULT 'PUBLIC_WEB'::text NOT NULL,
    evidence_reference text,
    CONSTRAINT brand_fuel_names_source_type_check CHECK ((source_type = ANY (ARRAY['OFFICIAL'::text, 'FIELD_VERIFIED'::text, 'STATION_REPORTED'::text, 'USER_REPORTED'::text, 'PUBLIC_WEB'::text, 'CLIENT_KNOWLEDGE'::text])))
);


--
-- Name: brand_service_catalog; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.brand_service_catalog (
    code text NOT NULL,
    brand text NOT NULL,
    label text NOT NULL,
    sort_order smallint DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL
);


--
-- Name: current_fuel_prices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.current_fuel_prices (
    station_id bigint NOT NULL,
    fuel_code text NOT NULL,
    price numeric(12,4) NOT NULL,
    unit text NOT NULL,
    currency character(3) DEFAULT 'PEN'::bpchar NOT NULL,
    reported_at timestamp with time zone,
    source text DEFAULT 'OSINERGMIN'::text NOT NULL,
    source_record_id text,
    imported_at timestamp with time zone DEFAULT now() NOT NULL,
    collected_at timestamp with time zone,
    verified_at timestamp with time zone,
    expires_at timestamp with time zone,
    confidence_level smallint,
    CONSTRAINT current_fuel_prices_confidence_ck CHECK (((confidence_level IS NULL) OR ((confidence_level >= 0) AND (confidence_level <= 100)))),
    CONSTRAINT current_fuel_prices_currency_ck CHECK ((currency = 'PEN'::bpchar)),
    CONSTRAINT current_fuel_prices_price_ck CHECK ((price > (0)::numeric)),
    CONSTRAINT current_fuel_prices_source_ck CHECK ((source = ANY (ARRAY['OFFICIAL'::text, 'FIELD_VERIFIED'::text, 'STATION_REPORTED'::text, 'USER_REPORTED'::text, 'DEMO'::text])))
);


--
-- Name: current_fuel_prices_backup_20261001; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.current_fuel_prices_backup_20261001 (
    station_id bigint,
    fuel_code text,
    price numeric(12,4),
    unit text,
    currency character(3),
    reported_at timestamp with time zone,
    source text,
    source_record_id text,
    imported_at timestamp with time zone,
    collected_at timestamp with time zone,
    verified_at timestamp with time zone,
    expires_at timestamp with time zone,
    confidence_level smallint
);


--
-- Name: dashboard_daily_metrics; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.dashboard_daily_metrics AS
 SELECT (timezone('America/Lima'::text, created_at))::date AS metric_date,
    count(*) AS total_events,
    count(DISTINCT telegram_chat_id) AS active_users,
    count(*) FILTER (WHERE (event_name = 'start_command'::text)) AS starts,
    count(*) FILTER (WHERE (event_name = 'location_shared'::text)) AS locations_shared,
    count(*) FILTER (WHERE (event_name = 'fuel_search'::text)) AS fuel_searches,
    count(*) FILTER (WHERE ((event_name = 'fuel_search'::text) AND (result_count > 0))) AS successful_searches,
    count(*) FILTER (WHERE (event_name = 'unrecognized_message'::text)) AS unrecognized_messages
   FROM public.bot_events
  GROUP BY ((timezone('America/Lima'::text, created_at))::date);


--
-- Name: dashboard_event_metrics; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.dashboard_event_metrics AS
 SELECT (timezone('America/Lima'::text, created_at))::date AS metric_date,
    event_name,
    count(*) AS events,
    count(DISTINCT telegram_chat_id) AS unique_users
   FROM public.bot_events
  GROUP BY ((timezone('America/Lima'::text, created_at))::date), event_name;


--
-- Name: dashboard_fuel_metrics; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.dashboard_fuel_metrics AS
 SELECT (timezone('America/Lima'::text, created_at))::date AS metric_date,
    fuel_code,
    count(*) AS searches,
    count(DISTINCT telegram_chat_id) AS unique_users,
    round(avg(result_count), 2) AS average_results
   FROM public.bot_events
  WHERE ((event_name = 'fuel_search'::text) AND (fuel_code IS NOT NULL))
  GROUP BY ((timezone('America/Lima'::text, created_at))::date), fuel_code;


--
-- Name: data_observations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_observations (
    id bigint NOT NULL,
    app_user_id bigint NOT NULL,
    station_id bigint NOT NULL,
    observation_type text NOT NULL,
    fuel_code text,
    reported_price numeric(10,2),
    service_code text,
    is_available boolean,
    promo_text text,
    reporter_latitude double precision,
    reporter_longitude double precision,
    gps_match boolean DEFAULT false NOT NULL,
    evidence_reference text,
    receipt_id bigint,
    status text DEFAULT 'PENDING_VALIDATION'::text NOT NULL,
    confidence_level smallint,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    collected_at timestamp with time zone DEFAULT now() NOT NULL,
    source_type text DEFAULT 'FIELD_VERIFIED'::text NOT NULL,
    raw_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    rejection_reason text,
    CONSTRAINT data_observations_confidence_level_check CHECK (((confidence_level IS NULL) OR ((confidence_level >= 0) AND (confidence_level <= 100)))),
    CONSTRAINT data_observations_observation_type_check CHECK ((observation_type = ANY (ARRAY['ESTACION'::text, 'PRECIO'::text, 'SERVICIO'::text, 'PROMOCION'::text, 'BANOS'::text]))),
    CONSTRAINT data_observations_precio_ck CHECK (((observation_type <> 'PRECIO'::text) OR ((fuel_code IS NOT NULL) AND (reported_price IS NOT NULL)))),
    CONSTRAINT data_observations_promocion_ck CHECK (((observation_type <> 'PROMOCION'::text) OR (promo_text IS NOT NULL))),
    CONSTRAINT data_observations_raw_payload_ck CHECK ((jsonb_typeof(raw_payload) = 'object'::text)),
    CONSTRAINT data_observations_servicio_ck CHECK (((observation_type <> ALL (ARRAY['SERVICIO'::text, 'BANOS'::text])) OR (is_available IS NOT NULL))),
    CONSTRAINT data_observations_source_type_ck CHECK ((source_type = ANY (ARRAY['OFFICIAL'::text, 'FIELD_VERIFIED'::text, 'STATION_REPORTED'::text, 'USER_REPORTED'::text, 'PUBLIC_WEB'::text]))),
    CONSTRAINT data_observations_status_check CHECK ((status = ANY (ARRAY['PENDING_VALIDATION'::text, 'APPROVED'::text, 'REJECTED'::text])))
);


--
-- Name: data_observations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.data_observations ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_observations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: fuel_price_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fuel_price_history (
    id bigint NOT NULL,
    station_id bigint NOT NULL,
    fuel_code text NOT NULL,
    price numeric(12,4) NOT NULL,
    unit text NOT NULL,
    currency character(3) DEFAULT 'PEN'::bpchar NOT NULL,
    reported_at timestamp with time zone,
    source text DEFAULT 'OSINERGMIN'::text NOT NULL,
    source_record_id text,
    imported_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT fuel_price_history_currency_ck CHECK ((currency = 'PEN'::bpchar)),
    CONSTRAINT fuel_price_history_price_ck CHECK ((price > (0)::numeric))
);


--
-- Name: fuel_price_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.fuel_price_history ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.fuel_price_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: fuel_products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fuel_products (
    code text NOT NULL,
    display_name text NOT NULL,
    category text NOT NULL,
    default_unit text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    CONSTRAINT fuel_products_category_ck CHECK ((category = ANY (ARRAY['GASOLINE'::text, 'DIESEL'::text, 'GLP'::text, 'GNV'::text, 'OTHER'::text])))
);


--
-- Name: ingestion_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingestion_runs (
    id bigint NOT NULL,
    source text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    status text DEFAULT 'RUNNING'::text NOT NULL,
    records_received integer DEFAULT 0 NOT NULL,
    records_upserted integer DEFAULT 0 NOT NULL,
    records_rejected integer DEFAULT 0 NOT NULL,
    source_reference text,
    error_summary text,
    CONSTRAINT ingestion_runs_status_ck CHECK ((status = ANY (ARRAY['RUNNING'::text, 'SUCCEEDED'::text, 'PARTIAL'::text, 'FAILED'::text])))
);


--
-- Name: ingestion_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ingestion_runs ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.ingestion_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: offer_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.offer_categories (
    code text NOT NULL,
    label text NOT NULL,
    icon text,
    sort_order smallint DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL
);


--
-- Name: purchase_receipts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_receipts (
    id bigint NOT NULL,
    app_user_id bigint NOT NULL,
    receipt_category text DEFAULT 'COMBUSTIBLE'::text NOT NULL,
    ruc_emisor text NOT NULL,
    station_id bigint,
    ruc_match boolean DEFAULT false NOT NULL,
    monto_total numeric(10,2),
    fecha_emision date,
    raw_qr_data text NOT NULL,
    captured_at timestamp with time zone DEFAULT now() NOT NULL,
    source_channel text DEFAULT 'whatsapp'::text NOT NULL,
    CONSTRAINT purchase_receipts_receipt_category_check CHECK ((receipt_category = ANY (ARRAY['COMBUSTIBLE'::text, 'GENERAL'::text])))
);


--
-- Name: TABLE purchase_receipts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.purchase_receipts IS 'Entidad propia, no atada a data_observations: hoy solo boletas de combustible, deja abierta la puerta a boletas generales para el cálculo futuro de actividad económica.';


--
-- Name: purchase_receipts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.purchase_receipts ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.purchase_receipts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: ref_brand_directory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ref_brand_directory (
    id integer NOT NULL,
    brand text NOT NULL,
    nombre_estacion text NOT NULL,
    direccion text NOT NULL,
    source_url text,
    matched_station_id bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: ref_brand_directory_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ref_brand_directory_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ref_brand_directory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ref_brand_directory_id_seq OWNED BY public.ref_brand_directory.id;


--
-- Name: service_catalog; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_catalog (
    code text NOT NULL,
    label text NOT NULL,
    icon text,
    sort_order smallint DEFAULT 0 NOT NULL,
    category text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    CONSTRAINT service_catalog_category_ck CHECK ((category = ANY (ARRAY['VEHICLE'::text, 'DRIVER'::text, 'SHOPPING'::text, 'FOOD'::text, 'FACILITY'::text])))
);


--
-- Name: station_brand_services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.station_brand_services (
    id bigint NOT NULL,
    station_id bigint NOT NULL,
    service_code text NOT NULL,
    is_available boolean DEFAULT true NOT NULL,
    source_type text DEFAULT 'PUBLIC_WEB'::text NOT NULL,
    collected_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone,
    evidence_reference text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT station_brand_services_source_type_check CHECK ((source_type = ANY (ARRAY['OFFICIAL'::text, 'FIELD_VERIFIED'::text, 'STATION_REPORTED'::text, 'USER_REPORTED'::text, 'PUBLIC_WEB'::text, 'CLIENT_KNOWLEDGE'::text])))
);


--
-- Name: station_brand_services_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.station_brand_services ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.station_brand_services_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: station_claims; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.station_claims (
    id bigint NOT NULL,
    station_id bigint NOT NULL,
    claimant_name text NOT NULL,
    claimant_ruc text NOT NULL,
    claimant_phone text NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    requested_at timestamp with time zone DEFAULT now() NOT NULL,
    resolved_at timestamp with time zone,
    CONSTRAINT station_claims_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'VERIFIED'::text, 'REJECTED'::text])))
);


--
-- Name: station_claims_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.station_claims ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.station_claims_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: stations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stations (
    id bigint NOT NULL,
    source text DEFAULT 'OSINERGMIN'::text NOT NULL,
    source_station_id text NOT NULL,
    registry_code text,
    ruc text,
    legal_name text,
    trade_name text NOT NULL,
    brand text,
    station_type text,
    status text,
    address text,
    department text,
    province text,
    district text,
    ubigeo character varying(6),
    latitude double precision,
    longitude double precision,
    location public.geometry(Point,4326),
    phone text,
    is_formal boolean,
    source_updated_at timestamp with time zone,
    imported_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    loyalty_program text,
    nearby_businesses text,
    other_notes text,
    field_comments text,
    CONSTRAINT stations_latitude_ck CHECK (((latitude IS NULL) OR ((latitude >= ('-90'::integer)::double precision) AND (latitude <= (90)::double precision)))),
    CONSTRAINT stations_longitude_ck CHECK (((longitude IS NULL) OR ((longitude >= ('-180'::integer)::double precision) AND (longitude <= (180)::double precision)))),
    CONSTRAINT stations_ubigeo_ck CHECK (((ubigeo IS NULL) OR ((ubigeo)::text ~ '^[0-9]{6}$'::text)))
);


--
-- Name: station_current_prices; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.station_current_prices AS
 SELECT s.id AS station_id,
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
   FROM ((public.stations s
     JOIN public.current_fuel_prices p ON ((p.station_id = s.id)))
     JOIN public.fuel_products fp ON ((fp.code = p.fuel_code)));


--
-- Name: VIEW station_current_prices; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.station_current_prices IS 'Vista de consulta para el bot; los precios deben atribuirse a su fuente oficial y mostrar reported_at.';


--
-- Name: station_offers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.station_offers (
    id bigint NOT NULL,
    station_id bigint NOT NULL,
    title text NOT NULL,
    description text,
    promo_code text,
    audience text DEFAULT 'GENERAL'::text NOT NULL,
    valid_from date,
    valid_until date,
    source_type text DEFAULT 'STATION_REPORTED'::text NOT NULL,
    status text DEFAULT 'ACTIVE'::text NOT NULL,
    collected_at timestamp with time zone DEFAULT now() NOT NULL,
    verified_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    offer_category_code text DEFAULT 'OTRA'::text NOT NULL,
    promotional_price numeric(12,2),
    discount_percent numeric(5,2),
    terms_and_conditions text,
    confidence_level smallint DEFAULT 50,
    evidence_reference text,
    CONSTRAINT station_offers_audience_check CHECK ((audience = ANY (ARRAY['GENERAL'::text, 'TAXISTA'::text, 'FLOTA'::text]))),
    CONSTRAINT station_offers_confidence_ck CHECK (((confidence_level IS NULL) OR ((confidence_level >= 0) AND (confidence_level <= 100)))),
    CONSTRAINT station_offers_dates_ck CHECK (((valid_from IS NULL) OR (valid_until IS NULL) OR (valid_until >= valid_from))),
    CONSTRAINT station_offers_discount_ck CHECK (((discount_percent IS NULL) OR ((discount_percent >= (0)::numeric) AND (discount_percent <= (100)::numeric)))),
    CONSTRAINT station_offers_price_ck CHECK (((promotional_price IS NULL) OR (promotional_price >= (0)::numeric))),
    CONSTRAINT station_offers_source_type_check CHECK ((source_type = ANY (ARRAY['OFFICIAL'::text, 'FIELD_VERIFIED'::text, 'STATION_REPORTED'::text, 'USER_REPORTED'::text, 'PUBLIC_WEB'::text]))),
    CONSTRAINT station_offers_status_check CHECK ((status = ANY (ARRAY['ACTIVE'::text, 'EXPIRED'::text, 'WITHDRAWN'::text])))
);


--
-- Name: station_offers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.station_offers ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.station_offers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: station_services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.station_services (
    id bigint NOT NULL,
    station_id bigint NOT NULL,
    service_code text NOT NULL,
    is_available boolean DEFAULT true NOT NULL,
    source_type text DEFAULT 'STATION_REPORTED'::text NOT NULL,
    collected_at timestamp with time zone DEFAULT now() NOT NULL,
    verified_at timestamp with time zone,
    expires_at timestamp with time zone,
    confidence_level smallint,
    evidence_reference text,
    verified_by text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    price numeric(12,2),
    currency character(3) DEFAULT 'PEN'::bpchar,
    details text,
    CONSTRAINT station_services_confidence_level_check CHECK (((confidence_level IS NULL) OR ((confidence_level >= 0) AND (confidence_level <= 100)))),
    CONSTRAINT station_services_currency_ck CHECK (((currency IS NULL) OR (currency = 'PEN'::bpchar))),
    CONSTRAINT station_services_price_ck CHECK (((price IS NULL) OR (price >= (0)::numeric))),
    CONSTRAINT station_services_source_type_check CHECK ((source_type = ANY (ARRAY['OFFICIAL'::text, 'FIELD_VERIFIED'::text, 'STATION_REPORTED'::text, 'USER_REPORTED'::text, 'PUBLIC_WEB'::text])))
);


--
-- Name: station_services_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.station_services ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.station_services_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: station_verifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.station_verifications (
    id bigint NOT NULL,
    station_claim_id bigint NOT NULL,
    method text NOT NULL,
    result text NOT NULL,
    notes text,
    verified_by text,
    verified_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT station_verifications_method_check CHECK ((method = ANY (ARRAY['RUC_MATCH'::text, 'PHONE_CALL'::text, 'MANUAL_REVIEW'::text]))),
    CONSTRAINT station_verifications_result_check CHECK ((result = ANY (ARRAY['PASSED'::text, 'FAILED'::text])))
);


--
-- Name: station_verifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.station_verifications ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.station_verifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: stations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.stations ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.stations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: stations_petroperu_backup_20261001; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stations_petroperu_backup_20261001 (
    id bigint,
    trade_name text,
    brand text,
    updated_at timestamp with time zone
);


--
-- Name: stg_osinergmin_evpc_20260930; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stg_osinergmin_evpc_20260930 (
    source_record_id text NOT NULL,
    nro_registro text NOT NULL,
    ruc text NOT NULL,
    razon_social text NOT NULL,
    departamento text NOT NULL,
    provincia text NOT NULL,
    distrito text NOT NULL,
    direccion text NOT NULL,
    fecha_registro_local timestamp without time zone NOT NULL,
    cod_producto text NOT NULL,
    producto text NOT NULL,
    precio_venta numeric(12,4) NOT NULL,
    unidad text NOT NULL,
    codigo_osinerg text NOT NULL,
    actividad text NOT NULL,
    cod_actividad text NOT NULL,
    marca text,
    ult_precio_dif_cero boolean NOT NULL,
    producto_activo boolean NOT NULL,
    canonical_fuel_code text,
    imported_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT stg_osinergmin_evpc_20260930_canonical_fuel_code_check CHECK (((canonical_fuel_code IS NULL) OR (canonical_fuel_code = ANY (ARRAY['REGULAR'::text, 'PREMIUM'::text, 'DIESEL_B5'::text, 'GLP_AUTOMOTOR'::text, 'GNV'::text])))),
    CONSTRAINT stg_osinergmin_evpc_20260930_precio_venta_check CHECK ((precio_venta > (0)::numeric))
);


--
-- Name: stg_osinergmin_evpc_reconciliation_20260930; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stg_osinergmin_evpc_reconciliation_20260930 (
    codigo_osinerg text NOT NULL,
    latest_nro_registro text,
    ruc text,
    razon_social text,
    departamento text,
    provincia text,
    distrito text,
    direccion text,
    actividad text,
    cod_actividad text,
    latest_evpc_registration_at timestamp without time zone,
    candidate_count bigint,
    candidate_station_ids bigint[],
    resolved_station_id bigint,
    match_method text,
    coordinate_records bigint,
    coordinate_pairs bigint,
    latitude double precision,
    longitude double precision,
    reconciled_at timestamp with time zone,
    CONSTRAINT evpc_reconciliation_match_method_ck CHECK ((match_method = ANY (ARRAY['EXACT_REGISTRY'::text, 'UNIQUE_CODE'::text, 'EXACT_ACTIVITY'::text, 'NEW_GEOCODED'::text, 'NEW_NO_COORDINATES'::text, 'UNRESOLVED'::text])))
);


--
-- Name: stg_osinergmin_prices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stg_osinergmin_prices (
    registro_hidrocarburos text NOT NULL,
    fuel_code text NOT NULL,
    price numeric(12,4) NOT NULL,
    reported_at timestamp with time zone NOT NULL
);


--
-- Name: stg_osinergmin_stations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stg_osinergmin_stations (
    registro_hidrocarburos text NOT NULL,
    razon_social text NOT NULL,
    departamento text NOT NULL,
    provincia text NOT NULL,
    distrito text NOT NULL,
    direccion text NOT NULL,
    full_address text NOT NULL,
    latitude double precision,
    longitude double precision,
    geocode_status text,
    geocode_formatted_addr text,
    geocoded_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: stg_petroperu_public_20260930; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stg_petroperu_public_20260930 (
    source_row_number integer,
    source_row_key text NOT NULL,
    source_name text NOT NULL,
    source_updated_at_local text,
    source_timezone text,
    extracted_at_utc timestamp with time zone,
    operator_name text,
    address text,
    district text,
    province text,
    department text,
    ruc text,
    osinergmin_registry text,
    map_url text,
    latitude numeric,
    longitude numeric,
    gasohol_premium numeric,
    gasohol_regular numeric,
    gasolina_premium numeric,
    gasolina_regular numeric,
    gasolina_84 numeric,
    diesel_b5_s50_uv numeric,
    diesel_b5_uv numeric,
    glp numeric,
    gnv numeric,
    quality_flags text,
    source_page text,
    source_report text
);


--
-- Name: totem_geocode_batch_national_001_20260930; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.totem_geocode_batch_national_001_20260930 (
    codigo_osinerg text,
    latest_nro_registro text,
    departamento text,
    provincia text,
    distrito text,
    direccion text,
    full_address text,
    address_fingerprint text,
    match_method text,
    batch_code text,
    status text,
    attempts integer,
    latitude double precision,
    longitude double precision,
    google_status text,
    location_type text,
    formatted_address text,
    last_http_status integer,
    last_error text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    geocoded_at timestamp with time zone
);


--
-- Name: totem_geocode_queue_history_20261001; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.totem_geocode_queue_history_20261001 (
    codigo_osinerg text,
    latest_nro_registro text,
    departamento text,
    provincia text,
    distrito text,
    direccion text,
    full_address text,
    address_fingerprint text,
    match_method text,
    batch_code text,
    status text,
    attempts integer,
    latitude double precision,
    longitude double precision,
    google_status text,
    location_type text,
    formatted_address text,
    last_http_status integer,
    last_error text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    geocoded_at timestamp with time zone,
    archived_at timestamp with time zone
);


--
-- Name: totem_geocode_queue_osinergmin_20260930; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.totem_geocode_queue_osinergmin_20260930 (
    codigo_osinerg text NOT NULL,
    latest_nro_registro text NOT NULL,
    departamento text NOT NULL,
    provincia text NOT NULL,
    distrito text NOT NULL,
    direccion text NOT NULL,
    full_address text NOT NULL,
    address_fingerprint text NOT NULL,
    match_method text NOT NULL,
    batch_code text,
    status text DEFAULT 'PENDING'::text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    latitude double precision,
    longitude double precision,
    google_status text,
    location_type text,
    formatted_address text,
    last_http_status integer,
    last_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    geocoded_at timestamp with time zone,
    CONSTRAINT totem_geocode_queue_osinergmin_20260930_attempts_check CHECK ((attempts >= 0)),
    CONSTRAINT totem_geocode_queue_osinergmin_20260930_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'IN_PROGRESS'::text, 'SUCCESS'::text, 'ZERO_RESULTS'::text, 'INVALID_RESPONSE'::text, 'ERROR'::text, 'REVIEW'::text])))
);


--
-- Name: ref_brand_directory id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_brand_directory ALTER COLUMN id SET DEFAULT nextval('public.ref_brand_directory_id_seq'::regclass);


--
-- Name: app_events app_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_events
    ADD CONSTRAINT app_events_pkey PRIMARY KEY (id);


--
-- Name: app_users app_users_channel_external_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_users
    ADD CONSTRAINT app_users_channel_external_uk UNIQUE (channel, external_id);


--
-- Name: app_users app_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_users
    ADD CONSTRAINT app_users_pkey PRIMARY KEY (id);


--
-- Name: bot_events bot_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bot_events
    ADD CONSTRAINT bot_events_pkey PRIMARY KEY (id);


--
-- Name: bot_users bot_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bot_users
    ADD CONSTRAINT bot_users_pkey PRIMARY KEY (telegram_chat_id);


--
-- Name: brand_fuel_names brand_fuel_names_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.brand_fuel_names
    ADD CONSTRAINT brand_fuel_names_pkey PRIMARY KEY (brand, fuel_code);


--
-- Name: brand_service_catalog brand_service_catalog_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.brand_service_catalog
    ADD CONSTRAINT brand_service_catalog_pkey PRIMARY KEY (code);


--
-- Name: current_fuel_prices current_fuel_prices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.current_fuel_prices
    ADD CONSTRAINT current_fuel_prices_pkey PRIMARY KEY (station_id, fuel_code);


--
-- Name: data_observations data_observations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_observations
    ADD CONSTRAINT data_observations_pkey PRIMARY KEY (id);


--
-- Name: fuel_price_history fuel_price_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fuel_price_history
    ADD CONSTRAINT fuel_price_history_pkey PRIMARY KEY (id);


--
-- Name: fuel_products fuel_products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fuel_products
    ADD CONSTRAINT fuel_products_pkey PRIMARY KEY (code);


--
-- Name: ingestion_runs ingestion_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingestion_runs
    ADD CONSTRAINT ingestion_runs_pkey PRIMARY KEY (id);


--
-- Name: offer_categories offer_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offer_categories
    ADD CONSTRAINT offer_categories_pkey PRIMARY KEY (code);


--
-- Name: purchase_receipts purchase_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_receipts
    ADD CONSTRAINT purchase_receipts_pkey PRIMARY KEY (id);


--
-- Name: ref_brand_directory ref_brand_directory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_brand_directory
    ADD CONSTRAINT ref_brand_directory_pkey PRIMARY KEY (id);


--
-- Name: service_catalog service_catalog_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_catalog
    ADD CONSTRAINT service_catalog_pkey PRIMARY KEY (code);


--
-- Name: station_brand_services station_brand_services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_brand_services
    ADD CONSTRAINT station_brand_services_pkey PRIMARY KEY (id);


--
-- Name: station_brand_services station_brand_services_station_id_service_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_brand_services
    ADD CONSTRAINT station_brand_services_station_id_service_code_key UNIQUE (station_id, service_code);


--
-- Name: station_claims station_claims_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_claims
    ADD CONSTRAINT station_claims_pkey PRIMARY KEY (id);


--
-- Name: station_offers station_offers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_offers
    ADD CONSTRAINT station_offers_pkey PRIMARY KEY (id);


--
-- Name: station_services station_services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_services
    ADD CONSTRAINT station_services_pkey PRIMARY KEY (id);


--
-- Name: station_services station_services_station_service_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_services
    ADD CONSTRAINT station_services_station_service_uk UNIQUE (station_id, service_code);


--
-- Name: station_verifications station_verifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_verifications
    ADD CONSTRAINT station_verifications_pkey PRIMARY KEY (id);


--
-- Name: stations stations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stations
    ADD CONSTRAINT stations_pkey PRIMARY KEY (id);


--
-- Name: stations stations_source_identity_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stations
    ADD CONSTRAINT stations_source_identity_uk UNIQUE (source, source_station_id);


--
-- Name: stg_osinergmin_evpc_20260930 stg_osinergmin_evpc_20260930_codigo_osinerg_cod_producto_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stg_osinergmin_evpc_20260930
    ADD CONSTRAINT stg_osinergmin_evpc_20260930_codigo_osinerg_cod_producto_key UNIQUE (codigo_osinerg, cod_producto);


--
-- Name: stg_osinergmin_evpc_20260930 stg_osinergmin_evpc_20260930_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stg_osinergmin_evpc_20260930
    ADD CONSTRAINT stg_osinergmin_evpc_20260930_pkey PRIMARY KEY (source_record_id);


--
-- Name: stg_osinergmin_evpc_reconciliation_20260930 stg_osinergmin_evpc_reconciliation_20260930_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stg_osinergmin_evpc_reconciliation_20260930
    ADD CONSTRAINT stg_osinergmin_evpc_reconciliation_20260930_pkey PRIMARY KEY (codigo_osinerg);


--
-- Name: stg_osinergmin_prices stg_osinergmin_prices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stg_osinergmin_prices
    ADD CONSTRAINT stg_osinergmin_prices_pkey PRIMARY KEY (registro_hidrocarburos, fuel_code);


--
-- Name: stg_osinergmin_stations stg_osinergmin_stations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stg_osinergmin_stations
    ADD CONSTRAINT stg_osinergmin_stations_pkey PRIMARY KEY (registro_hidrocarburos);


--
-- Name: stg_petroperu_public_20260930 stg_petroperu_public_20260930_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stg_petroperu_public_20260930
    ADD CONSTRAINT stg_petroperu_public_20260930_pkey PRIMARY KEY (source_row_key);


--
-- Name: totem_geocode_queue_osinergmin_20260930 totem_geocode_queue_osinergmin_20260930_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.totem_geocode_queue_osinergmin_20260930
    ADD CONSTRAINT totem_geocode_queue_osinergmin_20260930_pkey PRIMARY KEY (codigo_osinerg);


--
-- Name: app_events_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_events_created_at_idx ON public.app_events USING btree (created_at DESC);


--
-- Name: app_events_fuel_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_events_fuel_created_idx ON public.app_events USING btree (fuel_code, created_at DESC);


--
-- Name: app_events_name_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_events_name_created_idx ON public.app_events USING btree (event_name, created_at DESC);


--
-- Name: app_events_user_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_events_user_created_idx ON public.app_events USING btree (app_user_id, created_at DESC);


--
-- Name: app_users_location_gix; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_users_location_gix ON public.app_users USING gist (last_location);


--
-- Name: bot_events_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bot_events_created_at_idx ON public.bot_events USING btree (created_at DESC);


--
-- Name: bot_events_fuel_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bot_events_fuel_created_idx ON public.bot_events USING btree (fuel_code, created_at DESC);


--
-- Name: bot_events_name_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bot_events_name_created_idx ON public.bot_events USING btree (event_name, created_at DESC);


--
-- Name: bot_events_user_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bot_events_user_created_idx ON public.bot_events USING btree (telegram_chat_id, created_at DESC);


--
-- Name: bot_users_location_gix; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bot_users_location_gix ON public.bot_users USING gist (location);


--
-- Name: current_fuel_prices_lookup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX current_fuel_prices_lookup_idx ON public.current_fuel_prices USING btree (fuel_code, price);


--
-- Name: data_observations_review_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_observations_review_idx ON public.data_observations USING btree (status, collected_at DESC);


--
-- Name: data_observations_station_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_observations_station_idx ON public.data_observations USING btree (station_id, observation_type);


--
-- Name: data_observations_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_observations_status_idx ON public.data_observations USING btree (status, collected_at DESC);


--
-- Name: data_observations_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_observations_user_idx ON public.data_observations USING btree (app_user_id, collected_at DESC);


--
-- Name: evpc_reconciliation_method_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX evpc_reconciliation_method_idx ON public.stg_osinergmin_evpc_reconciliation_20260930 USING btree (match_method);


--
-- Name: evpc_reconciliation_station_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX evpc_reconciliation_station_idx ON public.stg_osinergmin_evpc_reconciliation_20260930 USING btree (resolved_station_id);


--
-- Name: fuel_price_history_imported_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fuel_price_history_imported_idx ON public.fuel_price_history USING btree (imported_at DESC);


--
-- Name: fuel_price_history_station_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fuel_price_history_station_idx ON public.fuel_price_history USING btree (station_id, fuel_code, reported_at DESC);


--
-- Name: purchase_receipts_station_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purchase_receipts_station_idx ON public.purchase_receipts USING btree (station_id);


--
-- Name: purchase_receipts_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purchase_receipts_user_idx ON public.purchase_receipts USING btree (app_user_id);


--
-- Name: station_claims_one_active_per_station; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX station_claims_one_active_per_station ON public.station_claims USING btree (station_id) WHERE (status = ANY (ARRAY['PENDING'::text, 'VERIFIED'::text]));


--
-- Name: station_offers_station_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX station_offers_station_idx ON public.station_offers USING btree (station_id);


--
-- Name: station_offers_totem_lookup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX station_offers_totem_lookup_idx ON public.station_offers USING btree (offer_category_code, status, valid_until);


--
-- Name: station_offers_validity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX station_offers_validity_idx ON public.station_offers USING btree (valid_from, valid_until);


--
-- Name: station_services_station_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX station_services_station_idx ON public.station_services USING btree (station_id);


--
-- Name: station_services_totem_lookup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX station_services_totem_lookup_idx ON public.station_services USING btree (service_code, is_available, expires_at);


--
-- Name: station_verifications_claim_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX station_verifications_claim_idx ON public.station_verifications USING btree (station_claim_id);


--
-- Name: stations_district_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stations_district_idx ON public.stations USING btree (department, province, district);


--
-- Name: stations_location_gix; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stations_location_gix ON public.stations USING gist (location);


--
-- Name: stations_registry_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stations_registry_code_idx ON public.stations USING btree (registry_code);


--
-- Name: stations_ruc_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stations_ruc_idx ON public.stations USING btree (ruc);


--
-- Name: stations_ubigeo_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stations_ubigeo_idx ON public.stations USING btree (ubigeo);


--
-- Name: totem_geocode_queue_address_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX totem_geocode_queue_address_idx ON public.totem_geocode_queue_osinergmin_20260930 USING btree (address_fingerprint);


--
-- Name: totem_geocode_queue_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX totem_geocode_queue_status_idx ON public.totem_geocode_queue_osinergmin_20260930 USING btree (status, batch_code, departamento);


--
-- Name: stations stations_set_location_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER stations_set_location_trg BEFORE INSERT OR UPDATE OF latitude, longitude, trade_name, address, status ON public.stations FOR EACH ROW EXECUTE FUNCTION public.set_station_location();


--
-- Name: app_events app_events_app_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_events
    ADD CONSTRAINT app_events_app_user_id_fkey FOREIGN KEY (app_user_id) REFERENCES public.app_users(id);


--
-- Name: app_events app_events_fuel_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_events
    ADD CONSTRAINT app_events_fuel_code_fkey FOREIGN KEY (fuel_code) REFERENCES public.fuel_products(code);


--
-- Name: bot_events bot_events_fuel_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bot_events
    ADD CONSTRAINT bot_events_fuel_code_fkey FOREIGN KEY (fuel_code) REFERENCES public.fuel_products(code);


--
-- Name: brand_fuel_names brand_fuel_names_fuel_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.brand_fuel_names
    ADD CONSTRAINT brand_fuel_names_fuel_code_fkey FOREIGN KEY (fuel_code) REFERENCES public.fuel_products(code);


--
-- Name: current_fuel_prices current_fuel_prices_fuel_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.current_fuel_prices
    ADD CONSTRAINT current_fuel_prices_fuel_code_fkey FOREIGN KEY (fuel_code) REFERENCES public.fuel_products(code);


--
-- Name: current_fuel_prices current_fuel_prices_station_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.current_fuel_prices
    ADD CONSTRAINT current_fuel_prices_station_id_fkey FOREIGN KEY (station_id) REFERENCES public.stations(id) ON DELETE CASCADE;


--
-- Name: data_observations data_observations_app_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_observations
    ADD CONSTRAINT data_observations_app_user_id_fkey FOREIGN KEY (app_user_id) REFERENCES public.app_users(id);


--
-- Name: data_observations data_observations_fuel_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_observations
    ADD CONSTRAINT data_observations_fuel_code_fkey FOREIGN KEY (fuel_code) REFERENCES public.fuel_products(code);


--
-- Name: data_observations data_observations_receipt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_observations
    ADD CONSTRAINT data_observations_receipt_id_fkey FOREIGN KEY (receipt_id) REFERENCES public.purchase_receipts(id);


--
-- Name: data_observations data_observations_service_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_observations
    ADD CONSTRAINT data_observations_service_code_fkey FOREIGN KEY (service_code) REFERENCES public.service_catalog(code);


--
-- Name: data_observations data_observations_station_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_observations
    ADD CONSTRAINT data_observations_station_id_fkey FOREIGN KEY (station_id) REFERENCES public.stations(id);


--
-- Name: fuel_price_history fuel_price_history_fuel_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fuel_price_history
    ADD CONSTRAINT fuel_price_history_fuel_code_fkey FOREIGN KEY (fuel_code) REFERENCES public.fuel_products(code);


--
-- Name: fuel_price_history fuel_price_history_station_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fuel_price_history
    ADD CONSTRAINT fuel_price_history_station_id_fkey FOREIGN KEY (station_id) REFERENCES public.stations(id) ON DELETE CASCADE;


--
-- Name: purchase_receipts purchase_receipts_app_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_receipts
    ADD CONSTRAINT purchase_receipts_app_user_id_fkey FOREIGN KEY (app_user_id) REFERENCES public.app_users(id);


--
-- Name: purchase_receipts purchase_receipts_station_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_receipts
    ADD CONSTRAINT purchase_receipts_station_id_fkey FOREIGN KEY (station_id) REFERENCES public.stations(id);


--
-- Name: ref_brand_directory ref_brand_directory_matched_station_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ref_brand_directory
    ADD CONSTRAINT ref_brand_directory_matched_station_id_fkey FOREIGN KEY (matched_station_id) REFERENCES public.stations(id);


--
-- Name: station_brand_services station_brand_services_service_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_brand_services
    ADD CONSTRAINT station_brand_services_service_code_fkey FOREIGN KEY (service_code) REFERENCES public.brand_service_catalog(code);


--
-- Name: station_brand_services station_brand_services_station_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_brand_services
    ADD CONSTRAINT station_brand_services_station_id_fkey FOREIGN KEY (station_id) REFERENCES public.stations(id) ON DELETE CASCADE;


--
-- Name: station_claims station_claims_station_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_claims
    ADD CONSTRAINT station_claims_station_id_fkey FOREIGN KEY (station_id) REFERENCES public.stations(id);


--
-- Name: station_offers station_offers_category_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_offers
    ADD CONSTRAINT station_offers_category_fkey FOREIGN KEY (offer_category_code) REFERENCES public.offer_categories(code);


--
-- Name: station_offers station_offers_station_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_offers
    ADD CONSTRAINT station_offers_station_id_fkey FOREIGN KEY (station_id) REFERENCES public.stations(id) ON DELETE CASCADE;


--
-- Name: station_services station_services_service_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_services
    ADD CONSTRAINT station_services_service_code_fkey FOREIGN KEY (service_code) REFERENCES public.service_catalog(code);


--
-- Name: station_services station_services_station_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_services
    ADD CONSTRAINT station_services_station_id_fkey FOREIGN KEY (station_id) REFERENCES public.stations(id) ON DELETE CASCADE;


--
-- Name: station_verifications station_verifications_station_claim_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_verifications
    ADD CONSTRAINT station_verifications_station_claim_id_fkey FOREIGN KEY (station_claim_id) REFERENCES public.station_claims(id);


--
-- PostgreSQL database dump complete
--

