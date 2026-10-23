function requireAuth(req, res, next) {
  if (!req.session || !req.session.user) {
    if (req.xhr || req.headers.accept?.includes('json')) {
      return res.status(401).json({ error: 'Chưa đăng nhập' });
    }
    return res.redirect('/auth/login?redirect=' + encodeURIComponent(req.originalUrl));
  }
  res.locals.currentUser = req.session.user;
  next();
}

function requireRole(allowedRoles) {
  return (req, res, next) => {
    if (!req.session || !req.session.user) {
      return res.redirect('/auth/login');
    }

    const userRole = req.session.user.role;
    
    // Check direct role or admin inheritance of manager role
    let hasPermission = false;
    if (Array.isArray(allowedRoles)) {
      if (allowedRoles.includes(userRole)) {
        hasPermission = true;
      } else if (userRole === 'admin' && allowedRoles.includes('manager')) {
        hasPermission = true;
      }
    } else if (allowedRoles === userRole || (userRole === 'admin' && allowedRoles === 'manager')) {
      hasPermission = true;
    }

    if (!hasPermission) {
      return res.status(403).render('partials/error', {
        title: '403 Cấm truy cập',
        statusCode: 403,
        message: 'Bạn không có quyền thực hiện hành động này (Yêu cầu vai trò: ' + (Array.isArray(allowedRoles) ? allowedRoles.join(', ') : allowedRoles) + ').'
      });
    }

    next();
  };
}

function checkGuest(req, res, next) {
  if (req.session && req.session.user) {
    return res.redirect('/assets');
  }
  next();
}

module.exports = {
  requireAuth,
  requireRole,
  checkGuest
};