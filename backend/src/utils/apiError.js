export class ApiError extends Error {
  /**
   * @param {number} status
   * @param {string} code
   * @param {string} message
   * @param {Record<string,string>} [fields] which input was wrong, and why
   */
  constructor(status, code, message, fields) {
    super(message);
    this.status = status;
    this.code = code;
    if (fields) this.fields = fields;
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

  /**
   * A form that was filled in wrongly, said field by field.
   *
   * The console's longer forms submit a dozen answers at once. A single
   * sentence ("name, mobile and providerKind are required") makes the person
   * filling it in re-read every box to work out which one it means, and says
   * nothing at all about the second problem. `fields` is keyed by the name the
   * form uses for its input, so the message lands next to the box it is about
   * and every problem is reported in one round trip rather than one per submit.
   *
   * `message` is still there for anything that only shows one line.
   */
  validation: (fields, message = 'Some of these answers need correcting.') =>
    new ApiError(422, 'VALIDATION', message, fields),

  internal: (message = 'Internal server error') => new ApiError(500, 'INTERNAL_ERROR', message),
};
