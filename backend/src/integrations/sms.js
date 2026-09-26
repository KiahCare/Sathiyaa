/**
 * SMS and OTP delivery.
 *
 * `SMS_PROVIDER` chooses the implementation; the default stub logs the OTP to
 * the console and lets the API echo it back as `devOtp`, which is what makes
 * the apps testable with no SMS account and no DLT registration.
 */
import { env } from '../config/env.js';
import * as stub from './providers/smsStub.js';
import * as real from './providers/sms.js';

const useReal = env.integrations.sms === 'msg91' || env.integrations.sms === 'twilio';
const impl = useReal ? real : stub;

export const providerName = useReal ? env.integrations.sms : 'stub';
export const isLive = useReal;

export const sendOtp = (...args) => impl.sendOtp(...args);
export const sendSms = (...args) => impl.sendSms(...args);
