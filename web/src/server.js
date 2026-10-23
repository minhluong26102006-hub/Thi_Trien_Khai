const path = require('path');
const express = require('express');
const session = require('express-session');
const dotenv = require('dotenv');

dotenv.config();

const csrfMiddleware = require('./middlewares/csrf');
const routes = require('./routes');

const app = express();
const PORT = process.env.PORT || 3000;

// Trust proxy for proper IP extraction and cookies behind reverse proxy
app.set('trust proxy', 1);

// View engine setup
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, '../views'));

// Static assets
app.use(express.static(path.join(__dirname, '../public')));
app.use('/uploads', express.static(path.join(__dirname, '../public/uploads')));

// Body parsers with size limit
app.use(express.urlencoded({ extended: true, limit: '1mb' }));
app.use(express.json({ limit: '1mb' }));

// Session configuration
app.use(session({
  name: 'asset_session',
  secret: process.env.SESSION_SECRET || 'fallback_secret_key_dtc245180061_asset',
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    sameSite: 'strict',
    secure: process.env.NODE_ENV === "production",
    maxAge: 8 * 60 * 60 * 1000 // 8 hours
  }
}));

// User and template helper variables
app.use((req, res, next) => {
  res.locals.currentUser = req.session?.user || null;
  res.locals.currentPath = req.path || '';
  res.locals.formatCurrency = (amount) => {
    return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(amount || 0);
  };
  res.locals.formatDate = (date) => {
    if (!date) return 'N/A';
    return new Date(date).toLocaleDateString('vi-VN');
  };
  res.locals.formatDateTime = (date) => {
    if (!date) return 'N/A';
    return new Date(date).toLocaleString('vi-VN');
  };
  next();
});

// CSRF Protection
app.use(csrfMiddleware);

// Mount Routes
app.use('/', routes);

// 404 Handler
app.use((req, res) => {
  res.status(404).render('partials/error', {
    title: '404 - Không tìm thấy trang',
    statusCode: 404,
    message: 'Địa chỉ bạn truy cập không tồn tại hoặc đã bị thay đổi.'
  });
});

// Central Error Handler
app.use((err, req, res, next) => {
  console.error('[Unhandled Error]', err);
  const isClientError = err.code === 'LIMIT_FILE_SIZE' ||
                        err.message?.includes('Định dạng tệp không hợp lệ') ||
                        err.message?.includes('Tệp');
  const status = isClientError ? 400 : 500;
  const message = err.code === 'LIMIT_FILE_SIZE'
    ? 'Tệp quá lớn! Kích thước tệp tải lên vượt quá giới hạn cho phép (Tối đa 2 MB).'
    : (err.message || 'Đã xảy ra sự cố nội bộ trong quá trình xử lý yêu cầu.');

  res.status(status).render('partials/error', {
    title: status === 400 ? 'Tệp không hợp lệ' : '500 - Lỗi máy chủ nội bộ',
    statusCode: status,
    message
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`[Asset Management] Server running on http://0.0.0.0:${PORT} (Node: ${process.version})`);
});