-- Personal Assistant Agent — Database Schema
-- Run this in Supabase → SQL Editor

CREATE TABLE IF NOT EXISTS usuarios (
    id          SERIAL PRIMARY KEY,
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    nombre      VARCHAR(100) NOT NULL,
    apellido    VARCHAR(100) NOT NULL,
    created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS gastos (
    id           SERIAL PRIMARY KEY,
    phone_number VARCHAR(20) NOT NULL REFERENCES usuarios(phone_number),
    monto        DECIMAL(10, 2) NOT NULL,
    categoria    VARCHAR(50) NOT NULL,
    descripcion  TEXT,
    fecha        TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gastos_phone_number ON gastos(phone_number);
CREATE INDEX IF NOT EXISTS idx_gastos_fecha        ON gastos(fecha DESC);
