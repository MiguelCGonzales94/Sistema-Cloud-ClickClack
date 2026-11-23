-- Estado compartido del backend (servicio sin estado para poder escalar a varias instancias).
--
-- Hasta la V4 estos cuatro datos vivían en la memoria de cada instancia, así que dos instancias
-- detrás de un balanceador no coincidían: un token revocado en una seguía válido en la otra, los
-- intentos fallidos se contaban por separado y una ceremonia WebAuthn podía "iniciar" en una y
-- "finalizar" en otra. Ahora viven en PostgreSQL, que ya es la única fuente de verdad.
--
-- Seguridad (OWASP A02): los tokens opacos (JWT revocados y enlaces de recuperación) se guardan
-- como huella SHA-256, nunca en claro; quien lea la tabla no puede reutilizarlos.
--
-- Todas las filas caducan: el código purga las vencidas al escribir, así las tablas no crecen sin
-- límite.

-- JWT revocados al cerrar sesión (HU02). Solo hace falta conservarlos hasta que el propio token
-- habría expirado.
CREATE TABLE token_revocado (
    token_hash CHAR(64) PRIMARY KEY,
    expira_en  TIMESTAMPTZ NOT NULL
);
CREATE INDEX ix_token_revocado_expira_en ON token_revocado (expira_en);

-- Intentos fallidos de inicio de sesión por correo (HU02). La clave es el correo enviado, exista o
-- no la cuenta, para que el bloqueo no delate qué cuentas existen. 320 es el máximo de una
-- dirección de correo.
CREATE TABLE intento_fallido (
    correo          VARCHAR(320) PRIMARY KEY,
    fallos          INTEGER      NOT NULL CHECK (fallos > 0),
    inicio_ventana  TIMESTAMPTZ  NOT NULL,
    bloqueado_hasta TIMESTAMPTZ
);
CREATE INDEX ix_intento_fallido_bloqueado_hasta
    ON intento_fallido (bloqueado_hasta) WHERE bloqueado_hasta IS NOT NULL;

-- Enlaces de recuperación de contraseña (HU03), de un solo uso y con vigencia limitada.
-- Sin clave foránea hacia usuario a propósito: es un token opaco de 30 minutos que se valida al
-- consumirlo (el servicio vuelve a cargar al usuario), y la tabla se escribe en una transacción
-- propia que no debe depender de la del llamador.
CREATE TABLE token_recuperacion (
    token_hash CHAR(64) PRIMARY KEY,
    usuario_id BIGINT      NOT NULL,
    expira_en  TIMESTAMPTZ NOT NULL
);
CREATE INDEX ix_token_recuperacion_expira_en ON token_recuperacion (expira_en);

-- Desafío criptográfico entre "iniciar" y "finalizar" de cada ceremonia WebAuthn. `contenido` es el
-- JSON de la librería (toJson/fromJson), no un objeto serializado de Java.
CREATE TABLE desafio_webauthn (
    id        UUID PRIMARY KEY,
    tipo      VARCHAR(20) NOT NULL CHECK (tipo IN ('REGISTRO', 'AUTENTICACION')),
    contenido TEXT        NOT NULL,
    expira_en TIMESTAMPTZ NOT NULL
);
CREATE INDEX ix_desafio_webauthn_expira_en ON desafio_webauthn (expira_en);
