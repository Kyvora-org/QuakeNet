-- ========================================================
-- QUAKENET: ESQUEMA OFICIAL DE BASE DE DATOS (FASES 2A & 2B)
-- ========================================================

-- Habilitar extensión PostGIS para cálculos geoespaciales
CREATE EXTENSION IF NOT EXISTS postgis;

-- --------------------------------------------------------
-- 1. TABLA: seismic_events
-- --------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seismic_events (
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

-- Habilitar RLS en seismic_events
ALTER TABLE public.seismic_events ENABLE ROW LEVEL SECURITY;

-- Índices en seismic_events
CREATE INDEX IF NOT EXISTS idx_seismic_events_detected_at ON public.seismic_events(detected_at);
CREATE INDEX IF NOT EXISTS idx_seismic_events_status ON public.seismic_events(status);

-- --------------------------------------------------------
-- 2. TABLA: triggers
-- --------------------------------------------------------
-- Almacena las detecciones de dispositivos individuales (STA/LTA superado)
-- Coordenadas nullable para admitir nodos sin GPS o sin señal satelital
CREATE TABLE IF NOT EXISTS public.triggers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID NOT NULL,
    session_id UUID NOT NULL,
    detected_at TIMESTAMP WITH TIME ZONE NOT NULL,
    latitude FLOAT8,                -- Nullable (fallback seguro)
    longitude FLOAT8,               -- Nullable (fallback seguro)
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

-- Asegurar que latitude y longitude permitan NULL si la tabla ya existía
ALTER TABLE public.triggers ALTER COLUMN latitude DROP NOT NULL;
ALTER TABLE public.triggers ALTER COLUMN longitude DROP NOT NULL;

-- Habilitar RLS en triggers
ALTER TABLE public.triggers ENABLE ROW LEVEL SECURITY;

-- Índices en triggers
CREATE INDEX IF NOT EXISTS idx_triggers_detected_at ON public.triggers(detected_at);
CREATE INDEX IF NOT EXISTS idx_triggers_node_id ON public.triggers(node_id);
CREATE INDEX IF NOT EXISTS idx_triggers_event_id ON public.triggers(event_id);

-- Índice geoespacial parcial para PostGIS (solo indexa registros con coordenadas reales)
CREATE INDEX IF NOT EXISTS idx_triggers_geom 
ON public.triggers USING GIST (ST_SetSRID(ST_MakePoint(longitude, latitude), 4326))
WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- --------------------------------------------------------
-- 3. POLÍTICAS RLS (Row Level Security)
-- --------------------------------------------------------

-- Permitir inserción anónima de triggers desde los teléfonos móviles
DROP POLICY IF EXISTS "Permitir insertar triggers anonimamente" ON public.triggers;
CREATE POLICY "Permitir insertar triggers anonimamente" 
ON public.triggers 
FOR INSERT 
TO public, anon, authenticated 
WITH CHECK (true);

-- No permitir lectura pública de triggers de otros nodos
DROP POLICY IF EXISTS "Denegar lectura publica de triggers individuales" ON public.triggers;
-- Por defecto en PostgreSQL, sin política SELECT para anon, la lectura queda completamente bloqueada.

-- Permitir lectura pública de eventos correlacionados confirmados
DROP POLICY IF EXISTS "Permitir lectura publica de eventos sismicos" ON public.seismic_events;
CREATE POLICY "Permitir lectura publica de eventos sismicos" 
ON public.seismic_events 
FOR SELECT 
TO public, anon, authenticated 
USING (true);

