// P5. LÍMITE DE PETICIONES del proxy (control OWASP A04/A05, patrón Throttling). Pasa por la URL pública y el balanceador.
// Una sola IP genera 80 peticiones/s durante 20 s contra la API sin credenciales. El proxy permite 20/s con ráfaga de 40
// por IP: lo que exceda debe recibir 429 (y el servicio no debe degradarse para los demás). Las respuestas válidas son 401
// (sin token); 429 indica que el límite actuó. No se mide capacidad, se comprueba la protección.
import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const limitadas = new Counter('respuestas_429');
export const options = {
  scenarios: { exceso: { executor: 'constant-arrival-rate', rate: 80, timeUnit: '1s', duration: '20s', preAllocatedVUs: 40, maxVUs: 100 } },
};
export default function () {
  const r = http.get(`${__ENV.URL_PUBLICA}/api/proyectos`, { tags: { name: 'GET /api/proyectos (sin token)' } });
  if (r.status === 429) limitadas.add(1);
  check(r, { 'respuesta esperada (401 o 429)': (x) => x.status === 401 || x.status === 429 });
}
