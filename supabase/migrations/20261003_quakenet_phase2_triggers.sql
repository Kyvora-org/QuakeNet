-- Habilitar extensión PostGIS para cálculos rápidos de distancia y agregaciones espaciales
CREATE EXTENSION IF NOT EXISTS postgis;

-- --------------------------------------------------------
-- TABLA: seismic_events
-- --------------------------------------------------------
-- Representa eventos sísmicos correlacionados o candidatos 
-- a partir de la agrupación de múltiples triggers.
CREATE TABLE public.seismic_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    status TEXT NOT NULL CHECK (status IN ('candidate', 'correlated', 'discarded', 'high_confidence')),
    detected_at TIMESTAMP WITH TIME ZONE NOT NULL,
    latitude FLOAT8 NOT NULL,
    longitude FLOAT8 NOT NULL,
    estimated_radius_km FLOAT8,
    node_count INTEGER NOT NULL DEFAULT 0,
    confidence FLOAT8 NOT NULL DEFAULT 0.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Habilitar seguridad a nivel de filas (RLS)
ALTER TABLE public.seismic_events ENABLE ROW LEVEL SECURITY;

-- Índice para busquedas geográficas (si se requiere PostGIS) y por tiempo
CREATE INDEX idx_seismic_events_detected_at ON public.seismic_events(detected_at);
CREATE INDEX idx_seismic_events_status ON public.seismic_events(status);

-- --------------------------------------------------------
-- TABLA: triggers
-- --------------------------------------------------------
-- Almacena temporalmente los registros de dispositivos individuales
-- cuyo algoritmo local (STA/LTA) superó el umbral.
CREATE TABLE public.triggers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID NOT NULL,
    session_id UUID NOT NULL,
    detected_at TIMESTAMP WITH TIME ZONE NOT NULL,
    latitude FLOAT8 NOT NULL,
    longitude FLOAT8 NOT NULL,
    location_accuracy_m FLOAT8,
    ratio FLOAT8 NOT NULL,
    peak_magnitude FLOAT8,
    duration_ms INTEGER,
    sampling_rate_hz FLOAT8,
    platform TEXT NOT NULL,
    app_version TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    event_id UUID REFERENCES public.seismic_events(id) ON DELETE SET NULL
);

-- Habilitar seguridad a nivel de filas (RLS)
ALTER TABLE public.triggers ENABLE ROW LEVEL SECURITY;

-- Índices de alto rendimiento para inserción y evaluación
CREATE INDEX idx_triggers_detected_at ON public.triggers(detected_at);
CREATE INDEX idx_triggers_node_id ON public.triggers(node_id);
CREATE INDEX idx_triggers_event_id ON public.triggers(event_id);
-- Si se requiere indexar espacialmente usando PostGIS
CREATE INDEX idx_triggers_geom ON public.triggers USING GIST (ST_SetSRID(ST_MakePoint(longitude, latitude), 4326));

-- --------------------------------------------------------
-- POLÍTICAS RLS (Row Level Security)
-- --------------------------------------------------------

-- 1. Políticas para triggers:
-- Cualquiera (incluso anónimos con llave publica) puede INSERTAR un trigger,
-- pero NINGÚN cliente público puede LEER los triggers de otros.
CREATE POLICY "Permitir insertar triggers anonimamente" 
ON public.triggers 
FOR INSERT 
TO public, anon, authenticated
WITH CHECK (true);

-- 2. Políticas para seismic_events:
-- Los clientes públicos pueden leer eventos que ya tengan cierta confirmación.
-- (La escritura solo se hará mediante Supabase Service Role Key en Edge Functions).
CREATE POLICY "Permitir lectura publica de eventos sismicos" 
ON public.seismic_events 
FOR SELECT 
TO public, anon, authenticated
USING (true);

-- --------------------------------------------------------
-- PROCEDIMIENTOS Y RETENCIÓN (CONCEPTUAL)
-- --------------------------------------------------------
-- En Supabase, para eliminar triggers antiguos periódicamente, 
-- se puede usar pg_cron. Ejemplo (no ejecutado por defecto para no perder datos en fase investigativa):
-- SELECT cron.schedule('purge_old_triggers', '0 0 * * *', $$ DELETE FROM triggers WHERE created_at < NOW() - INTERVAL '7 days' $$);
