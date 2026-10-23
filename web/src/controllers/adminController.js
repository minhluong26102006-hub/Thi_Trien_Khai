const bcrypt = require('bcryptjs');
const db = require('../config/db');
const { logAssetStatusChange } = require('../utils/logger');

function getAdminIndex(req, res) {
  res.render('admin/index', {
    title: 'Khu vực quản trị hệ thống'
  });
}

// ==================== ASSET CRUD ====================

async function getNewAssetForm(req, res) {
  try {
    const [categoriesResult, locationsResult] = await Promise.all([
      db.query('SELECT * FROM categories ORDER BY sort_order ASC, name ASC'),
      db.query('SELECT * FROM locations ORDER BY name ASC')
    ]);

    res.render('admin/asset_form', {
      title: 'Thêm tài sản / thiết bị mới',
      asset: null,
      categories: categoriesResult.rows,
      locations: locationsResult.rows,
      error: null
    });
  } catch (err) {
    console.error('Error loading asset form:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể mở biểu mẫu tạo tài sản.'
    });
  }
}

async function postCreateAsset(req, res) {
  const {
    asset_code, name, category_id, location_id,
    serial_number, purchase_date, purchase_price,
    useful_life_years, status, note
  } = req.body;

  const price = parseInt(purchase_price, 10);
  const lifeYears = parseInt(useful_life_years, 10);

  // Validation
  if (!asset_code || !name || !category_id || !location_id || !purchase_date) {
    return res.status(400).render('partials/error', {
      title: 'Dữ liệu không hợp lệ',
      statusCode: 400,
      message: 'Vui lòng nhập đầy đủ các thông tin bắt buộc!'
    });
  }

  if (isNaN(price) || price < 0) {
    return res.status(400).render('partials/error', {
      title: 'Giá mua không hợp lệ',
      statusCode: 400,
      message: 'Giá mua của tài sản phải là số không âm (>= 0)!'
    });
  }

  if (isNaN(lifeYears) || lifeYears <= 0) {
    return res.status(400).render('partials/error', {
      title: 'Hạn khấu hao không hợp lệ',
      statusCode: 400,
      message: 'Thời hạn khấu hao phải lớn hơn 0 (> 0 năm)!'
    });
  }

  try {
    // Check unique asset_code
    const existing = await db.query('SELECT id FROM assets WHERE asset_code = $1', [asset_code.trim().toUpperCase()]);
    if (existing.rows.length > 0) {
      return res.status(400).render('partials/error', {
        title: 'Mã tài sản đã tồn tại',
        statusCode: 400,
        message: `Mã tài sản "${asset_code}" đã tồn tại trong hệ thống. Vui lòng chọn mã khác!`
      });
    }

    // Determine image path: uploaded file or default category SVG
    let imagePath = '/images/assets/laptop.svg';
    if (req.file) {
      imagePath = `/uploads/${req.file.filename}`;
    } else {
      const catResult = await db.query('SELECT name FROM categories WHERE id = $1', [category_id]);
      const catName = catResult.rows[0]?.name?.toLowerCase() || '';
      if (catName.includes('chiếu')) imagePath = '/images/assets/projector.svg';
      else if (catName.includes('mạng')) imagePath = '/images/assets/network.svg';
      else if (catName.includes('màn hình')) imagePath = '/images/assets/monitor.svg';
      else if (catName.includes('nội thất')) imagePath = '/images/assets/furniture.svg';
      else if (catName.includes('dụng cụ')) imagePath = '/images/assets/tool.svg';
    }

    const insertResult = await db.query(
      `INSERT INTO assets (
         asset_code, name, category_id, location_id, serial_number,
         purchase_date, purchase_price, useful_life_years, status,
         image_path, note
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       RETURNING id`,
      [
        asset_code.trim().toUpperCase(),
        name.trim(),
        parseInt(category_id, 10),
        parseInt(location_id, 10),
        serial_number ? serial_number.trim() : null,
        purchase_date,
        price,
        lifeYears,
        status || 'available',
        imagePath,
        note ? note.trim() : null
      ]
    );

    res.redirect(`/assets/${insertResult.rows[0].id}`);
  } catch (err) {
    console.error('Error creating asset:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể thêm tài sản vào cơ sở dữ liệu.'
    });
  }
}

async function getEditAssetForm(req, res) {
  const { id } = req.params;

  try {
    const [assetResult, categoriesResult, locationsResult] = await Promise.all([
      db.query('SELECT * FROM assets WHERE id = $1', [id]),
      db.query('SELECT * FROM categories ORDER BY sort_order ASC, name ASC'),
      db.query('SELECT * FROM locations ORDER BY name ASC')
    ]);

    const asset = assetResult.rows[0];
    if (!asset) {
      return res.status(404).render('partials/error', {
        title: '404 Không tìm thấy',
        statusCode: 404,
        message: 'Tài sản không tồn tại!'
      });
    }

    res.render('admin/asset_form', {
      title: `Chỉnh sửa tài sản - ${asset.asset_code}`,
      asset,
      categories: categoriesResult.rows,
      locations: locationsResult.rows,
      error: null
    });
  } catch (err) {
    console.error('Error loading edit asset form:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tải biểu mẫu chỉnh sửa tài sản.'
    });
  }
}

async function postEditAsset(req, res) {
  const { id } = req.params;
  const {
    name, category_id, location_id,
    serial_number, purchase_date, purchase_price,
    useful_life_years, note
  } = req.body;

  const price = parseInt(purchase_price, 10);
  const lifeYears = parseInt(useful_life_years, 10);

  if (!name || !category_id || !location_id || !purchase_date) {
    return res.status(400).render('partials/error', {
      title: 'Dữ liệu không hợp lệ',
      statusCode: 400,
      message: 'Vui lòng nhập đầy đủ các thông tin bắt buộc!'
    });
  }

  if (isNaN(price) || price < 0 || isNaN(lifeYears) || lifeYears <= 0) {
    return res.status(400).render('partials/error', {
      title: 'Dữ liệu không hợp lệ',
      statusCode: 400,
      message: 'Giá mua phải >= 0 và hạn khấu hao phải > 0!'
    });
  }

  try {
    let updateImageClause = '';
    const params = [
      name.trim(),
      parseInt(category_id, 10),
      parseInt(location_id, 10),
      serial_number ? serial_number.trim() : null,
      purchase_date,
      price,
      lifeYears,
      note ? note.trim() : null,
      id
    ];

    if (req.file) {
      params.splice(8, 0, `/uploads/${req.file.filename}`);
      updateImageClause = `, image_path = $9`;
    }

    const sql = `
      UPDATE assets
      SET name = $1, category_id = $2, location_id = $3, serial_number = $4,
          purchase_date = $5, purchase_price = $6, useful_life_years = $7,
          note = $8 ${updateImageClause}
      WHERE id = $${params.length}
    `;

    await db.query(sql, params);
    res.redirect(`/assets/${id}`);
  } catch (err) {
    console.error('Error updating asset:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể cập nhật tài sản.'
    });
  }
}

async function postRetireAsset(req, res) {
  const { id } = req.params;
  const user = req.session.user;

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    const assetResult = await client.query('SELECT * FROM assets WHERE id = $1 FOR UPDATE', [id]);
    const asset = assetResult.rows[0];

    if (!asset) {
      await client.query('ROLLBACK');
      return res.status(404).render('partials/error', {
        title: '404 Không tìm thấy',
        statusCode: 404,
        message: 'Tài sản không tồn tại!'
      });
    }

    // Do NOT retire asset if currently borrowed
    if (asset.status === 'borrowed') {
      await client.query('ROLLBACK');
      return res.status(400).render('partials/error', {
        title: 'Không thể thanh lý',
        statusCode: 400,
        message: 'Không thể thanh lý tài sản đang được mượn! Vui lòng thu hồi thiết bị trước.'
      });
    }

    const prevStatus = asset.status;
    await client.query(`UPDATE assets SET status = 'retired' WHERE id = $1`, [id]);
    logAssetStatusChange(asset.asset_code, prevStatus, 'retired', user.username);

    await client.query('COMMIT');
    res.redirect(`/assets/${id}`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error retiring asset:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Có lỗi xảy ra khi thanh lý tài sản.'
    });
  } finally {
    client.release();
  }
}

// ==================== CATEGORIES & LOCATIONS ====================

async function getCategories(req, res) {
  try {
    const result = await db.query(`
      SELECT c.*, COUNT(a.id) AS asset_count
      FROM categories c
      LEFT JOIN assets a ON c.id = a.category_id
      GROUP BY c.id
      ORDER BY c.sort_order ASC, c.name ASC
    `);

    res.render('admin/categories', {
      title: 'Quản lý loại tài sản',
      categories: result.rows
    });
  } catch (err) {
    console.error('Error fetching categories:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tải danh sách loại tài sản.'
    });
  }
}

async function postCreateCategory(req, res) {
  const { name, sort_order } = req.body;
  if (!name || !name.trim()) {
    return res.redirect('/admin/categories');
  }

  try {
    await db.query(
      `INSERT INTO categories (name, sort_order) VALUES ($1, $2)`,
      [name.trim(), parseInt(sort_order, 10) || 0]
    );
    res.redirect('/admin/categories');
  } catch (err) {
    console.error('Error creating category:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể thêm loại tài sản.'
    });
  }
}

async function getLocations(req, res) {
  try {
    const result = await db.query(`
      SELECT l.*, COUNT(a.id) AS asset_count
      FROM locations l
      LEFT JOIN assets a ON l.id = a.location_id
      GROUP BY l.id
      ORDER BY l.name ASC
    `);

    res.render('admin/locations', {
      title: 'Quản lý vị trí / phòng ban',
      locations: result.rows
    });
  } catch (err) {
    console.error('Error fetching locations:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tải danh sách vị trí.'
    });
  }
}

async function postCreateLocation(req, res) {
  const { name, description } = req.body;
  if (!name || !name.trim()) {
    return res.redirect('/admin/locations');
  }

  try {
    await db.query(
      `INSERT INTO locations (name, description) VALUES ($1, $2)`,
      [name.trim(), description ? description.trim() : null]
    );
    res.redirect('/admin/locations');
  } catch (err) {
    console.error('Error creating location:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể thêm vị trí mới.'
    });
  }
}

// ==================== USER MANAGEMENT ====================

async function getUsers(req, res) {
  try {
    const result = await db.query('SELECT * FROM users ORDER BY role ASC, id ASC');
    res.render('admin/users', {
      title: 'Quản lý người dùng hệ thống',
      users: result.rows
    });
  } catch (err) {
    console.error('Error fetching users:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tải danh sách tài khoản.'
    });
  }
}

async function postCreateUser(req, res) {
  const { username, email, password, full_name, department, role } = req.body;

  if (!username || !email || !password || !full_name || !department || !role) {
    return res.status(400).render('partials/error', {
      title: 'Dữ liệu không hợp lệ',
      statusCode: 400,
      message: 'Vui lòng nhập đầy đủ thông tin tài khoản!'
    });
  }

  try {
    const existing = await db.query(
      'SELECT id FROM users WHERE username = $1 OR email = $2',
      [username.trim(), email.trim().toLowerCase()]
    );
    if (existing.rows.length > 0) {
      return res.status(400).render('partials/error', {
        title: 'Tài khoản đã tồn tại',
        statusCode: 400,
        message: 'Tên đăng nhập hoặc email đã được sử dụng!'
      });
    }

    const salt = await bcrypt.genSalt(10);
    const passwordHash = await bcrypt.hash(password, salt);

    await db.query(
      `INSERT INTO users (username, email, password_hash, full_name, department, role, is_active)
       VALUES ($1, $2, $3, $4, $5, $6, true)`,
      [username.trim(), email.trim().toLowerCase(), passwordHash, full_name.trim(), department.trim(), role]
    );

    res.redirect('/admin/users');
  } catch (err) {
    console.error('Error creating user:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tạo tài khoản mới.'
    });
  }
}

async function postToggleUserActive(req, res) {
  const { id } = req.params;
  const currentUserId = req.session.user.id;

  // Requirement: KHÔNG cho khóa chính mình!
  if (parseInt(id, 10) === currentUserId) {
    return res.status(400).render('partials/error', {
      title: 'Hành động bị cấm',
      statusCode: 400,
      message: 'Bạn không được phép khóa tài khoản của chính mình!'
    });
  }

  try {
    await db.query(`UPDATE users SET is_active = NOT is_active WHERE id = $1`, [id]);
    res.redirect('/admin/users');
  } catch (err) {
    console.error('Error toggling user active state:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể thay đổi trạng thái tài khoản.'
    });
  }
}

module.exports = {
  getAdminIndex,
  getNewAssetForm,
  postCreateAsset,
  getEditAssetForm,
  postEditAsset,
  postRetireAsset,
  getCategories,
  postCreateCategory,
  getLocations,
  postCreateLocation,
  getUsers,
  postCreateUser,
  postToggleUserActive
};