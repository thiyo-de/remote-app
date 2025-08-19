import morgan from "morgan";

export function httpLogger() {
  // compact dev logger
  return morgan(":method :url :status :res[content-length] - :response-time ms");
}

export function log(...args) {
  console.log("[srv]", ...args);
}

export function warn(...args) {
  console.warn("[srv][warn]", ...args);
}

export function err(...args) {
  console.error("[srv][err]", ...args);
}
