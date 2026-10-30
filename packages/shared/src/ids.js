import { customAlphabet } from "nanoid";
import { ID_PREFIXES } from "./enums.js";

const nano = customAlphabet("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", 12);

/**
 * New prefixed id, e.g. newId("player") → "ply_V1StGXR8Z5jd".
 * @param {keyof typeof ID_PREFIXES} kind
 */
export function newId(kind) {
  return `${ID_PREFIXES[kind]}_${nano()}`;
}
