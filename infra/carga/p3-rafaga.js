// P3. RÁFAGA DE SINCRONIZACIÓN con identificadores repetidos (cola sin conexión que reintenta).
// 2 000 marcaciones en 60 s (33/s) tomadas de un conjunto de 500 uuidCliente: cada uuid llega ~4 veces, también
// desde instancias distintas. Criterio: SIN DUPLICADOS (una fila por uuid) y sin pérdidas.
//
// Los uuid son DETERMINISTAS (prefijo + índice): el código del contexto inicial de k6 se ejecuta por separado en
// cada usuario virtual, así que un conjunto "aleatorio" sería distinto en cada uno y no habría repetidos entre
// instancias. Con uuid derivados del índice, todos comparten el mismo conjunto y después se puede contar en la
// base: filas con ese prefijo <= 500 aunque se hayan enviado 2 000 peticiones.
import { iniciarSesion, marcar, destino, UMBRALES } from './lib.js';

const POOL = 500;
const PREFIJO = __ENV.PREFIJO_UUID || '5b3e0001-0000-4000-8000-';
const uuidDe = (i) => PREFIJO + i.toString(16).padStart(12, '0');

export const options = {
  scenarios: {
    rafaga: {
      executor: 'constant-arrival-rate', rate: 33, timeUnit: '1s', duration: '60s',
      preAllocatedVUs: 60, maxVUs: 200,
    },
  },
  thresholds: UMBRALES,
};
export function setup() { return { token: iniciarSesion() }; }
export default function (datos) {
  marcar(datos.token, destino(), uuidDe(Math.floor(Math.random() * POOL)));
}
