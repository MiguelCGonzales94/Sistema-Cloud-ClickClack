// Biblioteca común de las pruebas de carga (k6). Mide la operación real de un colaborador:
//   - lecturas autenticadas (verifica el JWT y consulta la lista de revocados en PostgreSQL en CADA petición),
//   - y el registro de marcaciones (escritura, con idempotencia por uuidCliente).
//
// Variables de entorno:
//   OBJETIVOS   URLs base de los backends separadas por comas. Cada usuario virtual se "fija" a uno
//               (VU % n), como lo haría el reparto de un balanceador. 1 URL = 1 instancia; 2 URLs = 2 instancias.
//   CLAVE       contraseña del usuario de prueba            USUARIO_ID, DISPOSITIVO_ID
//
// Se apunta a los backends directamente (puerto 8080 de cada nodo, red privada) y no al Nginx público porque
// el proxy limita a 20 peticiones/s por IP (control OWASP A04): una prueba desde una sola IP medería ese
// límite y no la capacidad del servicio. El límite se comprueba aparte (ver p5-limite-nginx.js).
import http from 'k6/http';
import { check, fail } from 'k6';

export const OBJETIVOS = (__ENV.OBJETIVOS || '').split(',').filter((x) => x);
export const USUARIO_ID = Number(__ENV.USUARIO_ID || 0);
export const DISPOSITIVO_ID = Number(__ENV.DISPOSITIVO_ID || 0);
const CORREO = __ENV.CORREO || 'carga.k6@example.test';

export function uuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}

// Un solo inicio de sesión para toda la prueba (el login está limitado a 10/min por IP y es CPU intensivo por bcrypt).
// El token se usa luego contra TODAS las instancias: demuestra que la sesión vale en cualquiera (JWT con el mismo secreto).
export function iniciarSesion() {
  if (OBJETIVOS.length === 0) fail('Falta OBJETIVOS');
  const r = http.post(`${OBJETIVOS[0]}/api/auth/login`, JSON.stringify({ correo: CORREO, password: __ENV.CLAVE }),
    { headers: { 'Content-Type': 'application/json' }, tags: { name: 'POST /api/auth/login' } });
  if (!check(r, { 'login 200': (x) => x.status === 200 })) fail(`login falló: HTTP ${r.status}`);
  return r.json('token');
}

export function destino() {
  return OBJETIVOS[(__VU - 1) % OBJETIVOS.length];
}

function cabeceras(token) {
  return { headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' } };
}

export function leerYo(token, base) {
  const r = http.get(`${base}/api/auth/yo`, { ...cabeceras(token), tags: { name: 'GET /api/auth/yo' } });
  check(r, { 'yo 200': (x) => x.status === 200 });
}

export function leerIncidencias(token, base) {
  const r = http.get(`${base}/api/incidencias/mias`, { ...cabeceras(token), tags: { name: 'GET /api/incidencias/mias' } });
  check(r, { 'incidencias 200': (x) => x.status === 200 });
}

export function leerAsignaciones(token, base) {
  const r = http.get(`${base}/api/asignaciones/mias`, { ...cabeceras(token), tags: { name: 'GET /api/asignaciones/mias' } });
  check(r, { 'asignaciones 200': (x) => x.status === 200 });
}

export function marcar(token, base, uuidCliente) {
  const cuerpo = {
    uuidCliente: uuidCliente || uuid(),
    usuarioId: USUARIO_ID,
    dispositivoId: DISPOSITIVO_ID,
    tipoEvento: 'SALIDA',
    horaEvento: new Date(Date.now() - 2000).toISOString(),
    latitud: -12.0464,
    longitud: -77.0428,
    precisionMetros: 10.5,
  };
  const r = http.post(`${base}/api/marcaciones`, JSON.stringify(cuerpo), { ...cabeceras(token), tags: { name: 'POST /api/marcaciones' } });
  check(r, { 'marcación 201': (x) => x.status === 201 });
  return r;
}

// Mezcla de una jornada: 45 % lecturas del perfil, 15 % incidencias, 15 % asignaciones y 25 % marcaciones.
export function operacionTipica(token) {
  const base = destino();
  const p = Math.random();
  if (p < 0.45) leerYo(token, base);
  else if (p < 0.60) leerIncidencias(token, base);
  else if (p < 0.75) leerAsignaciones(token, base);
  else marcar(token, base);
}

// Criterio de aceptación del proyecto: p95 < 2 s y menos de 1 % de errores.
export const UMBRALES = {
  http_req_duration: ['p(95)<2000'],
  http_req_failed: ['rate<0.01'],
};
