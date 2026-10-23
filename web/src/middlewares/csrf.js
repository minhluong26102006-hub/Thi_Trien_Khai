const crypto = require('crypto');

function csrfMiddleware(req, res, next) {
  // Ensure session exists
  if (!req.session) {
    return next(new Error('Session required for CSRF protection'));
  }

  // Generate CSRF token if not already in session
  if (!req.session.csrfToken) {
    req.session.csrfToken = crypto.randomBytes(32).toString('hex');
  }

  // Provide to EJS views via res.locals
  res.locals.csrfToken = req.session.csrfToken;

  // Safe HTTP methods do not require CSRF validation
  const safeMethods = ['GET', 'HEAD', 'OPTIONS'];
  if (safeMethods.includes(req.method)) {
    return next();
  }

  // Exclude healthcheck if called via POST
  if (req.path === '/health') {
    return next();
  }

  // Extract CSRF token from body, headers, or query string (for multipart forms)
  const token = req.body?._csrf ||
                req.headers['x-csrf-token'] ||
                req.headers['csrf-token'] ||
                req.query?._csrf;

  if (!token || token !== req.session.csrfToken) {
    return res.status(403).render('partials/error', {
      title: '403 Lỗi bảo mật CSRF',
      statusCode: 403,
      message: 'Yêu cầu bị từ chối do CSRF Token không hợp lệ hoặc đã hết hạn. Vui lòng tải lại trang và thử lại.'
    });
  }

  next();
}

module.exports = csrfMiddleware;