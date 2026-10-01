import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createApp } from './app.js';

const databasePath = process.env.DATABASE_PATH
  ? resolve(process.env.DATABASE_PATH)
  : fileURLToPath(new URL('../data/habitapp.sqlite', import.meta.url));
mkdirSync(dirname(databasePath), { recursive: true });
const { app, close } = createApp({ databasePath });
const port = Number(process.env.PORT ?? 3000);
const host = process.env.HOST ?? '127.0.0.1';
const server = app.listen(port, host, () => console.log(`HabitApp API: http://${host}:${port}`));
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.once(signal, () => server.close(() => { close(); process.exit(0); }));
}
