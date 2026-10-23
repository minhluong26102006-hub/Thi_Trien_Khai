function getClientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (forwarded) {
    const list = forwarded.split(',');
    return list[0].trim();
  }
  return req.ip || req.connection?.remoteAddress || '127.0.0.1';
}

function logLoginSuccess(req, username) {
  const ip = getClientIp(req);
  console.log(`LOGIN_SUCCESS ip=${ip} user=${username}`);
}

function logLoginFailed(req, username, reason) {
  const ip = getClientIp(req);
  console.log(`LOGIN_FAILED ip=${ip} user=${username} reason=${reason}`);
}

function logAssetStatusChange(assetCode, fromStatus, toStatus, username) {
  console.log(`ASSET_STATUS_CHANGE asset=${assetCode} from=${fromStatus} to=${toStatus} by=${username}`);
}

function logOverdueViewed(count, username) {
  console.log(`LOAN_OVERDUE_VIEWED count=${count} by=${username}`);
}

module.exports = {
  getClientIp,
  logLoginSuccess,
  logLoginFailed,
  logAssetStatusChange,
  logOverdueViewed
};