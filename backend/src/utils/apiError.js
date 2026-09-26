export class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export const Errors = {
  badRequest: (code, message) => new ApiError(400, code, message),
  unauthorized: (message = 'Unauthorized') => new ApiError(401, 'UNAUTHORIZED', message),

  /**
   * A sign-in that failed, without saying which half of it failed.
   *
   * Everywhere a person can sign themselves up — a customer, a provider — the
   * server says plainly that there is no account for this number, because the
   * app needs to offer to create one. Nobody signs themselves up as an admin
   * or as a business partner: those accounts are made in the office. So on
   * those two endpoints the distinction buys a legitimate user nothing, and
   * hands anyone who can reach the API a way to find out which addresses are
   * administrators one request at a time.
   */
  invalidCredentials: (message = 'Those details are not right. Check them and try again.') =>
    new ApiError(401, 'INVALID_CREDENTIALS', message),
  forbidden: (message = 'Forbidden') => new ApiError(403, 'FORBIDDEN', message),
  notFound: (message = 'Not found') => new ApiError(404, 'NOT_FOUND', message),
  conflict: (code, message) => new ApiError(409, code, message),
  unprocessable: (code, message) => new ApiError(422, code, message),
  internal: (message = 'Internal server error') => new ApiError(500, 'INTERNAL_ERROR', message),
};
