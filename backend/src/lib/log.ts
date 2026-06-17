export function log(stage: string, msg: string): void {
  console.log(`[${new Date().toISOString()}] ${stage.padEnd(16)} ${msg}`);
}

export function warn(stage: string, msg: string): void {
  console.warn(`[${new Date().toISOString()}] ${stage.padEnd(16)} ⚠ ${msg}`);
}
