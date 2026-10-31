-- ============================================================================
-- MIGRACIÓN FASE 2C.2: MOTOR DE CORRELACIÓN SÍSMICA DISTRIBUIDA Y CONSENSO
-- ============================================================================

-- 1. Ampliación de columnas para métricas de consenso en public.seismic_events
ALTER TABLE public.seismic_events
ADD COLUMN IF NOT EXISTS independent_node_count FLOAT8 DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS spatial_cluster_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS avg_sta_lta FLOAT8,
ADD COLUMN IF NOT EXISTS max_peak_magnitude FLOAT8,
ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
ADD COLUMN IF NOT EXISTS last_correlated_at TIMESTAMP WITH TIME ZONE DEFAULT now();

-- 2. Ampliación de control de procesamiento en public.triggers
ALTER TABLE public.triggers
ADD COLUMN IF NOT EXISTS processed BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS spatial_cell TEXT;

-- 3. Índices optimizados para consulta y correlación rápida
CREATE INDEX IF NOT EXISTS idx_triggers_unprocessed 
ON public.triggers(processed, detected_at) 
WHERE processed = false;

CREATE INDEX IF NOT EXISTS idx_seismic_events_active 
ON public.seismic_events(status, detected_at) 
WHERE status IN ('candidate', 'correlated');

-- 4. Tabla de auditoría y telemetría de ejecuciones del motor
CREATE TABLE IF NOT EXISTS public.correlation_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    executed_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    triggers_evaluated INTEGER NOT NULL DEFAULT 0,
    events_created INTEGER NOT NULL DEFAULT 0,
    events_updated INTEGER NOT NULL DEFAULT 0,
    execution_time_ms INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'completed'
);

ALTER TABLE public.correlation_runs ENABLE ROW LEVEL SECURITY;

-- 5. FUNCIÓN PRINCIPAL DE CORRELACIÓN Y CONSENSO (PL/pgSQL)
CREATE OR REPLACE FUNCTION public.fn_correlate_triggers()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_lock_acquired BOOLEAN;
    v_triggers_evaluated INTEGER := 0;
    v_events_created INTEGER := 0;
    v_events_updated INTEGER := 0;
    v_trg RECORD;
    v_target_event_id UUID;
    v_candidate_trigger_ids UUID[];
    v_event_record RECORD;
    v_cell_count INTEGER;
    v_n_indep FLOAT8;
    v_k_cells INTEGER;
    v_center_lat FLOAT8;
    v_center_lon FLOAT8;
    v_max_dist_m FLOAT8;
    v_avg_ratio FLOAT8;
    v_max_mag FLOAT8;
    v_avg_quality FLOAT8;
    v_time_spread_s FLOAT8;
    v_phi_vol FLOAT8;
    v_phi_space FLOAT8;
    v_phi_quality FLOAT8;
    v_phi_time FLOAT8;
    v_confidence FLOAT8;
    v_new_status TEXT;
    v_rejection TEXT;
BEGIN
    v_start_time := clock_timestamp();

    -- 5.1. Concurrencia e Idempotencia: Adquirir cerrojo consultivo exclusivo (Key: 7429104)
    -- Si otro proceso ya está ejecutando la correlación, salimos de inmediato sin bloquear la base de datos
    v_lock_acquired := pg_try_advisory_xact_lock(7429104);
    IF NOT v_lock_acquired THEN
        RETURN jsonb_build_object(
            'status', 'skipped',
            'reason', 'Another correlation process is currently active'
        );
    END IF;

    -- 5.2. Asignar 'spatial_cell' (resolución ~500m) a los triggers que no lo tengan
    UPDATE public.triggers
    SET spatial_cell = round(latitude::numeric, 2)::text || ':' || round(longitude::numeric, 2)::text
    WHERE processed = false 
      AND spatial_cell IS NULL 
      AND latitude IS NOT NULL 
      AND longitude IS NOT NULL;

    -- 5.3. Iterar sobre los triggers pendientes de procesamiento (ordenados cronológicamente)
    FOR v_trg IN 
        SELECT id, node_id, session_id, detected_at, latitude, longitude, 
               location_accuracy_m, ratio, peak_magnitude, spatial_cell
        FROM public.triggers
        WHERE processed = false
        ORDER BY detected_at ASC
        FOR UPDATE SKIP LOCKED
    LOOP
        v_triggers_evaluated := v_triggers_evaluated + 1;
        v_target_event_id := NULL;

        -- 5.3.1. Intentar asociar con un evento activo existente (candidate o correlated)
        -- Ventana temporal: +-15 segundos respecto a la detección
        -- Ventana espacial: <= 50 km de distancia geodésica del centroide del evento
        IF v_trg.latitude IS NOT NULL AND v_trg.longitude IS NOT NULL THEN
            SELECT id INTO v_target_event_id
            FROM public.seismic_events
            WHERE status IN ('candidate', 'correlated')
              AND detected_at BETWEEN (v_trg.detected_at - INTERVAL '15 seconds') 
                                  AND (v_trg.detected_at + INTERVAL '15 seconds')
              AND ST_DWithin(
                    ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography,
                    ST_SetSRID(ST_MakePoint(v_trg.longitude, v_trg.latitude), 4326)::geography,
                    50000 -- 50 km
                  )
            ORDER BY detected_at ASC
            LIMIT 1;
        ELSE
            -- Si el trigger no tiene GPS, se asocia solo por coincidencia temporal estrecha (+-5s)
            SELECT id INTO v_target_event_id
            FROM public.seismic_events
            WHERE status IN ('candidate', 'correlated')
              AND detected_at BETWEEN (v_trg.detected_at - INTERVAL '5 seconds') 
                                  AND (v_trg.detected_at + INTERVAL '5 seconds')
            ORDER BY detected_at ASC
            LIMIT 1;
        END IF;

        IF v_target_event_id IS NOT NULL THEN
            -- Asociar trigger al evento existente
            UPDATE public.triggers
            SET event_id = v_target_event_id,
                processed = true
            WHERE id = v_trg.id;
            
            v_events_updated := v_events_updated + 1;
        ELSE
            -- 5.3.2. Si no hay evento existente, buscar si hay al menos 2 pares compatibles entre los pendientes
            IF v_trg.latitude IS NOT NULL AND v_trg.longitude IS NOT NULL THEN
                SELECT array_agg(id) INTO v_candidate_trigger_ids
                FROM (
                    SELECT id
                    FROM public.triggers
                    WHERE processed = false
                      AND id != v_trg.id
                      AND latitude IS NOT NULL 
                      AND longitude IS NOT NULL
                      AND detected_at BETWEEN (v_trg.detected_at - INTERVAL '15 seconds') 
                                          AND (v_trg.detected_at + INTERVAL '15 seconds')
                      AND ST_DWithin(
                            ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography,
                            ST_SetSRID(ST_MakePoint(v_trg.longitude, v_trg.latitude), 4326)::geography,
                            50000 -- 50 km
                          )
                    LIMIT 2
                ) sub;
            ELSE
                v_candidate_trigger_ids := NULL;
            END IF;

            -- Si encontramos al menos 2 pares (total >= 3 nodos compatibles), creamos un nuevo evento candidato
            IF v_candidate_trigger_ids IS NOT NULL AND array_length(v_candidate_trigger_ids, 1) >= 2 THEN
                INSERT INTO public.seismic_events (
                    status,
                    detected_at,
                    latitude,
                    longitude,
                    estimated_radius_km,
                    node_count,
                    confidence
                ) VALUES (
                    'candidate',
                    v_trg.detected_at,
                    v_trg.latitude,
                    v_trg.longitude,
                    1.0,
                    1 + array_length(v_candidate_trigger_ids, 1),
                    10.0
                )
                RETURNING id INTO v_target_event_id;

                -- Vincular los triggers al nuevo evento candidato
                UPDATE public.triggers
                SET event_id = v_target_event_id,
                    processed = true
                WHERE id = v_trg.id OR id = ANY(v_candidate_trigger_ids);

                v_events_created := v_events_created + 1;
            ELSE
                -- 5.3.3. Si el trigger tiene más de 60 segundos de antigüedad y no encontró pares, descartarlo
                IF v_trg.detected_at < (now() - INTERVAL '60 seconds') THEN
                    UPDATE public.triggers
                    SET processed = true,
                        event_id = NULL
                    WHERE id = v_trg.id;
                END IF;
            END IF;
        END IF;
    END LOOP;

    -- 5.4. RECALCULAR MÉTRICAS MATEMÁTICAS Y TRANSICIÓN DE ESTADOS EN EVENTOS ACTIVOS
    FOR v_event_record IN
        SELECT id, detected_at, status
        FROM public.seismic_events
        WHERE status IN ('candidate', 'correlated')
    LOOP
        -- Calcular Centroide y métricas agregadas de los triggers asociados
        SELECT 
            COUNT(DISTINCT node_id),
            COUNT(DISTINCT spatial_cell),
            AVG(latitude) FILTER (WHERE latitude IS NOT NULL),
            AVG(longitude) FILTER (WHERE longitude IS NOT NULL),
            AVG(ratio),
            MAX(peak_magnitude),
            AVG(
                0.40 * LEAST(1.0, GREATEST(0.1, (ratio - 3.0) / 12.0)) +
                0.30 * (CASE 
                            WHEN COALESCE(peak_magnitude, 0.1) < 0.01 THEN 0.3
                            WHEN COALESCE(peak_magnitude, 0.1) BETWEEN 0.01 AND 1.2 THEN 1.0
                            ELSE GREATEST(0.1, 1.0 - (COALESCE(peak_magnitude, 0.1) - 1.2) / 1.8)
                        END) +
                0.30 * (CASE 
                            WHEN location_accuracy_m IS NOT NULL AND location_accuracy_m <= 50 THEN 1.0
                            WHEN location_accuracy_m IS NOT NULL AND location_accuracy_m <= 200 THEN 0.8
                            WHEN location_accuracy_m IS NOT NULL AND location_accuracy_m <= 1000 THEN 0.5
                            ELSE 0.2
                        END)
            ),
            EXTRACT(EPOCH FROM (MAX(detected_at) - MIN(detected_at)))
        INTO 
            v_cell_count,
            v_k_cells,
            v_center_lat,
            v_center_lon,
            v_avg_ratio,
            v_max_mag,
            v_avg_quality,
            v_time_spread_s
        FROM public.triggers
        WHERE event_id = v_event_record.id;

        -- Calcular N_indep usando entropía espacial sublineal anti-edificio:
        -- w(n_c) = 1.0 si n_c = 1; else 1.0 + 0.3 * ln(n_c)
        SELECT COALESCE(SUM(
            CASE 
                WHEN cell_n = 1 THEN 1.0
                ELSE 1.0 + 0.3 * ln(cell_n)
            END
        ), 0.0)
        INTO v_n_indep
        FROM (
            SELECT COALESCE(spatial_cell, 'NO_GPS_' || node_id::text) AS cell_id, COUNT(DISTINCT node_id) AS cell_n
            FROM public.triggers
            WHERE event_id = v_event_record.id
            GROUP BY 1
        ) sub_cells;

        -- Calcular radio de dispersión máxima en km respecto al centroide
        IF v_center_lat IS NOT NULL AND v_center_lon IS NOT NULL THEN
            SELECT COALESCE(MAX(
                ST_Distance(
                    ST_SetSRID(ST_MakePoint(v_center_lon, v_center_lat), 4326)::geography,
                    ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
                ) / 1000.0
            ), 1.0)
            INTO v_max_dist_m
            FROM public.triggers
            WHERE event_id = v_event_record.id
              AND latitude IS NOT NULL AND longitude IS NOT NULL;
        ELSE
            v_max_dist_m := 1.0;
        END IF;

        -- Ponderación de los 4 pilares de confianza:
        v_phi_vol     := LEAST(1.0, v_n_indep / 100.0);
        v_phi_space   := 0.5 * LEAST(1.0, COALESCE(v_k_cells, 1)::float / 10.0) + 
                         0.5 * LEAST(1.0, v_max_dist_m / 30.0);
        v_phi_quality := COALESCE(v_avg_quality, 0.5);
        v_phi_time    := GREATEST(0.1, 1.0 - (COALESCE(v_time_spread_s, 0.0) / 7.5));

        v_confidence := ROUND((100.0 * (
            0.35 * v_phi_vol +
            0.30 * v_phi_space +
            0.20 * v_phi_quality +
            0.15 * v_phi_time
        ))::numeric, 1);

        -- Determinación del estado objetivo:
        v_new_status := v_event_record.status;
        v_rejection := NULL;

        IF v_n_indep >= 100.0 AND COALESCE(v_k_cells, 0) >= 10 AND v_confidence >= 80.0 THEN
            v_new_status := 'high_confidence';
        ELSIF v_n_indep >= 10.0 AND COALESCE(v_k_cells, 0) >= 3 AND v_confidence >= 40.0 THEN
            v_new_status := 'correlated';
        ELSIF v_event_record.detected_at < (now() - INTERVAL '90 seconds') THEN
            -- Si la ventana cerró y quedó confinado a una sola célula o < 3 nodos
            IF COALESCE(v_k_cells, 0) <= 1 OR v_n_indep < 3.0 THEN
                v_new_status := 'discarded';
                v_rejection := 'Falsa alarma local: señal confinada espacialmente sin propagación';
            END IF;
        END IF;

        -- Actualizar evento con las métricas consolidadas
        UPDATE public.seismic_events
        SET status = v_new_status,
            latitude = COALESCE(v_center_lat, latitude),
            longitude = COALESCE(v_center_lon, longitude),
            estimated_radius_km = ROUND(v_max_dist_m::numeric, 2),
            node_count = (SELECT COUNT(*) FROM public.triggers WHERE event_id = v_event_record.id),
            independent_node_count = ROUND(v_n_indep::numeric, 2),
            spatial_cluster_count = COALESCE(v_k_cells, 0),
            confidence = v_confidence,
            avg_sta_lta = ROUND(COALESCE(v_avg_ratio, 0.0)::numeric, 2),
            max_peak_magnitude = ROUND(COALESCE(v_max_mag, 0.0)::numeric, 3),
            rejection_reason = COALESCE(v_rejection, rejection_reason),
            last_correlated_at = now(),
            updated_at = now()
        WHERE id = v_event_record.id;
    END LOOP;

    v_end_time := clock_timestamp();

    -- 5.5. Registrar ejecución en la tabla de auditoría
    INSERT INTO public.correlation_runs (
        triggers_evaluated,
        events_created,
        events_updated,
        execution_time_ms,
        status
    ) VALUES (
        v_triggers_evaluated,
        v_events_created,
        v_events_updated,
        ROUND((EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000)::numeric)::integer,
        'completed'
    );

    RETURN jsonb_build_object(
        'status', 'success',
        'triggers_evaluated', v_triggers_evaluated,
        'events_created', v_events_created,
        'events_updated', v_events_updated,
        'execution_time_ms', ROUND((EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000)::numeric)::integer
    );
END;
$$;

-- 6. PERMISOS Y SEGURIDAD (RLS)
-- Permitir invocación de la función mediante RPC a usuarios autenticados y clave de servicio
REVOKE EXECUTE ON FUNCTION public.fn_correlate_triggers() FROM public;
GRANT EXECUTE ON FUNCTION public.fn_correlate_triggers() TO anon, authenticated, service_role;
