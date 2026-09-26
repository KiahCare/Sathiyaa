import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';

/** role: 'customer' | 'provider' | 'business_agent' | 'admin' */
export function signToken({ role, id, name }) {
  return jwt.sign({ role, id, name }, env.jwt.secret, { expiresIn: env.jwt.expiresIn });
}

export function verifyToken(token) {
  return jwt.verify(token, env.jwt.secret);
}
