// P4. ESTRÉS: aumento progresivo de usuarios (sin pausa entre operaciones salvo 0,2 s) hasta encontrar el punto de quiebre
// y el recurso que lo causa. Cada escalón dura 45 s. No aborta: se quiere ver DÓNDE y CÓMO se degrada (latencia, errores, CPU, conexiones a BD).
import { sleep } from 'k6';
import { iniciarSesion, operacionTipica } from './lib.js';

export const options = {
  scenarios: {
    estres: {
      executor: 'ramping-vus', startVUs: 0,
      stages: [
        { duration: '45s', target: 25 }, { duration: '45s', target: 50 }, { duration: '45s', target: 100 },
        { duration: '45s', target: 150 }, { duration: '45s', target: 200 }, { duration: '20s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
};
export function setup() { return { token: iniciarSesion() }; }
export default function (datos) {
  operacionTipica(datos.token);
  sleep(0.2);
}
