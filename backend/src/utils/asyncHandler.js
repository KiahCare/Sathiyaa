/** Wraps an async express handler so rejected promises reach errorHandler middleware. */
export const asyncHandler = (fn) => (req, res, next) => {
  Promise.resolve(fn(req, res, next)).catch(next);
};
