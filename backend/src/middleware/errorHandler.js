import { ApiError } from '../utils/apiError.js';

export function notFoundHandler(req, res) {
  res.status(404).json({ error: { code: 'ROUTE_NOT_FOUND', message: `No route ${req.method} ${req.originalUrl}` } });
}

// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, next) {
  if (err instanceof ApiError) {
    return res.status(err.status).json({ error: { code: err.code, message: err.message } });
  }

  // mysql2 duplicate key etc.
  if (err && err.code === 'ER_DUP_ENTRY') {
    return res.status(409).json({ error: { code: 'DUPLICATE', message: 'Record already exists' } });
  }

  // A row that other rows still point at.
  //
  // This came back as a 500 reading "Something went wrong", which is the
  // least useful thing a console can say: an admin deleting a provider who
  // had once been *asked* about a booking saw a generic failure, with no way
  // to tell it apart from the server being down. It is a refusal, not a
  // fault, and it is told as one.
  if (err && (err.code === 'ER_ROW_IS_REFERENCED_2' || err.code === 'ER_ROW_IS_REFERENCED')) {
    return res.status(409).json({
      error: {
        code: 'IN_USE',
        message: 'This record is still referenced by other records and cannot be deleted. '
          + 'Block it instead, so the history stays intact.',
      },
    });
  }

  console.error('[error]', err);
  res.status(500).json({ error: { code: 'INTERNAL_ERROR', message: 'Something went wrong' } });
}
