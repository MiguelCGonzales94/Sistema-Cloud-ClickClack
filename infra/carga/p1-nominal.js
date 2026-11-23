// P1. Carga NOMINAL: 10 usuarios concurrentes con pausa de 0,5-1,5 s entre operaciones (un colaborador no martilla la API).
// Plan original: 10 min. Aquí 3 min (limitación de crédito y de tiempo de la semana); se declara en el informe.
// Criterio: p95 < 2 s y errores < 1 %.
import { sleep } from 'k6';
import { iniciarSesion, operacionTipica, UMBRALES } from './lib.js';

export const options = {
  scenarios: { nominal: { executor: 'constant-vus', vus: 10, duration: __ENV.DURACION || '3m' } },
  thresholds: UMBRALES,
};
export function setup() { return { token: iniciarSesion() }; }
export default function (datos) {
  operacionTipica(datos.token);
  sleep(0.5 + Math.random());
}
