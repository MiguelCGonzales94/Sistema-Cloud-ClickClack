// P2. PICO DE INGRESO: rampa hasta 50 usuarios concurrentes (la hora de entrada concentra las marcaciones).
// Plan original: rampa de 5 min. Aquí 2 min de rampa + 1 min sostenido + 20 s de descenso.
// Criterio: p95 < 2 s y errores < 1 %, memoria < 85 %.
import { sleep } from 'k6';
import { iniciarSesion, operacionTipica, UMBRALES } from './lib.js';

export const options = {
  scenarios: {
    pico: {
      executor: 'ramping-vus', startVUs: 0,
      stages: [
        { duration: '2m', target: 50 },
        { duration: '1m', target: 50 },
        { duration: '20s', target: 0 },
      ],
    },
  },
  thresholds: UMBRALES,
};
export function setup() { return { token: iniciarSesion() }; }
export default function (datos) {
  operacionTipica(datos.token);
  sleep(0.3 + Math.random() * 0.7);
}
