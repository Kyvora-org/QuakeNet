-- Fase 2B.1: Permitir coordenadas nulas cuando el nodo no tenga GPS activo o permiso denegado
-- Esto asegura que nunca se inventen coordenadas sintéticas (0.0, 0.0) y se respete la integridad física.

ALTER TABLE public.triggers
ALTER COLUMN latitude DROP NOT NULL;

ALTER TABLE public.triggers
ALTER COLUMN longitude DROP NOT NULL;
