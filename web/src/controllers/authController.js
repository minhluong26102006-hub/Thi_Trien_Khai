const bcrypt = require('bcryptjs');
const db = require('../config/db');
const { logLoginSuccess, logLoginFailed } = require('../utils/logger');

function getLogin(req, res) {
  res.render('auth/login', {
    title: 'Đăng nhập hệ thống',
    error: req.query.error || null,
    registered: req.query.registered === 'true',
    username: ''
  });
}

async function postLogin(req, res) {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).render('auth/login', {
      title: 'Đăng nhập hệ thống',
      error: 'Vui lòng nhập đầy đủ tên đăng nhập và mật khẩu!',
      registered: false,
      username: username || ''
    });
  }

  try {
    const result = await db.query('SELECT * FROM users WHERE username = $1', [username.trim()]);
    const user = result.rows[0];

    if (!user) {
      logLoginFailed(req, username.trim(), 'unknown_user');
      return res.status(401).render('auth/login', {
        title: 'Đăng nhập hệ thống',
        error: 'Tài khoản hoặc mật khẩu không chính xác!',
        registered: false,
        username
      });
    }

    if (!user.is_active) {
      logLoginFailed(req, username.trim(), 'inactive');
      return res.status(403).render('auth/login', {
        title: 'Đăng nhập hệ thống',
        error: 'Tài khoản của bạn đã bị khóa hoặc chưa kích hoạt. Vui lòng liên hệ quản trị viên!',
        registered: false,
        username
      });
    }

    const isMatch = await bcrypt.compare(password, user.password_hash);
    if (!isMatch) {
      logLoginFailed(req, username.trim(), 'wrong_password');
      return res.status(401).render('auth/login', {
        title: 'Đăng nhập hệ thống',
        error: 'Tài khoản hoặc mật khẩu không chính xác!',
        registered: false,
        username
      });
    }

    // Login successful
    logLoginSuccess(req, user.username);
    req.session.user = {
      id: user.id,
      username: user.username,
      full_name: user.full_name,
      email: user.email,
      department: user.department,
      role: user.role
    };

    const redirectUrl = req.body.redirect || '/assets';
    res.redirect(redirectUrl);
  } catch (err) {
    console.error('Error during login:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Có lỗi xảy ra trong quá trình xử lý đăng nhập.'
    });
  }
}

function getRegister(req, res) {
  res.render('auth/register', {
    title: 'Đăng ký tài khoản nhân viên',
    error: null,
    formData: {}
  });
}

async function postRegister(req, res) {
  const { username, email, password, confirm_password, full_name, department } = req.body;
  const formData = { username, email, full_name, department };

  if (!username || !email || !password || !confirm_password || !full_name || !department) {
    return res.status(400).render('auth/register', {
      title: 'Đăng ký tài khoản nhân viên',
      error: 'Vui lòng điền đầy đủ tất cả các trường thông tin!',
      formData
    });
  }

  if (password.length < 6) {
    return res.status(400).render('auth/register', {
      title: 'Đăng ký tài khoản nhân viên',
      error: 'Mật khẩu phải có độ dài tối thiểu 6 ký tự!',
      formData
    });
  }

  if (password !== confirm_password) {
    return res.status(400).render('auth/register', {
      title: 'Đăng ký tài khoản nhân viên',
      error: 'Mật khẩu xác nhận không khớp!',
      formData
    });
  }

  try {
    // Check existing username or email
    const existing = await db.query(
      'SELECT username, email FROM users WHERE username = $1 OR email = $2',
      [username.trim(), email.trim().toLowerCase()]
    );

    if (existing.rows.length > 0) {
      const match = existing.rows[0];
      const errMsg = match.username === username.trim()
        ? 'Tên đăng nhập đã được sử dụng!'
        : 'Địa chỉ email đã được đăng ký!';
      return res.status(400).render('auth/register', {
        title: 'Đăng ký tài khoản nhân viên',
        error: errMsg,
        formData
      });
    }

    const salt = await bcrypt.genSalt(10);
    const passwordHash = await bcrypt.hash(password, salt);

    await db.query(
      `INSERT INTO users (username, email, password_hash, full_name, department, role, is_active)
       VALUES ($1, $2, $3, $4, $5, 'employee', true)`,
      [username.trim(), email.trim().toLowerCase(), passwordHash, full_name.trim(), department.trim()]
    );

    res.redirect('/auth/login?registered=true');
  } catch (err) {
    console.error('Error during registration:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể đăng ký tài khoản. Vui lòng thử lại sau.'
    });
  }
}

function logout(req, res) {
  req.session.destroy((err) => {
    if (err) {
      console.error('Logout error:', err);
    }
    res.clearCookie('connect.sid');
    res.redirect('/auth/login');
  });
}

module.exports = {
  getLogin,
  postLogin,
  getRegister,
  postRegister,
  logout
};