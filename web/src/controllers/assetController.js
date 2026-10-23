const db = require('../config/db');

function calculateDepreciation(purchasePrice, purchaseDate, usefulLifeYears) {
  const pDate = new Date(purchaseDate);
  const now = new Date();
  const diffTime = Math.max(0, now - pDate);
  const yearsUsed = diffTime / (1000 * 60 * 60 * 24 * 365.25);
  const fraction = Math.max(0, 1 - (yearsUsed / usefulLifeYears));
  const remainingValue = Math.round(Number(purchasePrice) * fraction);
  return {
    yearsUsed: yearsUsed.toFixed(1),
    remainingValue,
    depreciationPercent: Math.min(100, Math.round((1 - fraction) * 100))
  };
}

async function getAssets(req, res) {
  try {
    const { q, category, location, status, sort, page } = req.query;

    const currentPage = Math.max(1, parseInt(page, 10) || 1);
    const limit = 9;
    const offset = (currentPage - 1) * limit;

    const conditions = [];
    const params = [];
    let paramIdx = 1;

    if (q && q.trim()) {
      conditions.push(`(a.name ILIKE $${paramIdx} OR a.asset_code ILIKE $${paramIdx})`);
      params.push(`%${q.trim()}%`);
      paramIdx++;
    }

    if (category) {
      conditions.push(`a.category_id = $${paramIdx}`);
      params.push(parseInt(category, 10));
      paramIdx++;
    }

    if (location) {
      conditions.push(`a.location_id = $${paramIdx}`);
      params.push(parseInt(location, 10));
      paramIdx++;
    }

    if (status) {
      conditions.push(`a.status = $${paramIdx}`);
      params.push(status);
      paramIdx++;
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    let orderBy = 'a.id DESC';
    if (sort === 'name_asc') orderBy = 'a.name ASC';
    else if (sort === 'name_desc') orderBy = 'a.name DESC';
    else if (sort === 'price_asc') orderBy = 'a.purchase_price ASC';
    else if (sort === 'price_desc') orderBy = 'a.purchase_price DESC';
    else if (sort === 'date_asc') orderBy = 'a.purchase_date ASC';
    else if (sort === 'date_desc') orderBy = 'a.purchase_date DESC';

    // Count total items
    const countSql = `SELECT COUNT(*) AS total FROM assets a ${whereClause}`;
    const countResult = await db.query(countSql, params);
    const totalItems = parseInt(countResult.rows[0].total, 10);
    const totalPages = Math.ceil(totalItems / limit) || 1;

    // Fetch assets with joined category and location
    const assetsSql = `
      SELECT a.*, c.name AS category_name, l.name AS location_name
      FROM assets a
      JOIN categories c ON a.category_id = c.id
      JOIN locations l ON a.location_id = l.id
      ${whereClause}
      ORDER BY ${orderBy}
      LIMIT $${paramIdx} OFFSET $${paramIdx + 1}
    `;
    const assetsResult = await db.query(assetsSql, [...params, limit, offset]);

    // Fetch categories and locations for filter dropdowns
    const categoriesResult = await db.query('SELECT * FROM categories ORDER BY sort_order ASC, name ASC');
    const locationsResult = await db.query('SELECT * FROM locations ORDER BY name ASC');

    res.render('assets/index', {
      title: 'Danh mục tài sản & thiết bị',
      assets: assetsResult.rows,
      categories: categoriesResult.rows,
      locations: locationsResult.rows,
      filters: { q, category, location, status, sort },
      pagination: {
        currentPage,
        totalPages,
        totalItems
      }
    });
  } catch (err) {
    console.error('Error fetching assets:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tải danh sách tài sản.'
    });
  }
}

async function getAssetDetail(req, res) {
  const { id } = req.params;

  try {
    const assetResult = await db.query(
      `SELECT a.*, c.name AS category_name, l.name AS location_name
       FROM assets a
       JOIN categories c ON a.category_id = c.id
       JOIN locations l ON a.location_id = l.id
       WHERE a.id = $1`,
      [id]
    );

    const asset = assetResult.rows[0];
    if (!asset) {
      return res.status(404).render('partials/error', {
        title: '404 Không tìm thấy',
        statusCode: 404,
        message: 'Không tìm thấy tài sản yêu cầu!'
      });
    }

    const depreciation = calculateDepreciation(
      asset.purchase_price,
      asset.purchase_date,
      asset.useful_life_years
    );

    // Fetch loan history for this asset
    const loansResult = await db.query(
      `SELECT l.loan_code, l.requested_at, l.borrowed_at, l.returned_at, l.status,
              u.full_name AS borrower_name, u.department,
              li.condition_out, li.condition_returned
       FROM loan_items li
       JOIN loans l ON li.loan_id = l.id
       JOIN users u ON l.user_id = u.id
       WHERE li.asset_id = $1
       ORDER BY l.requested_at DESC
       LIMIT 10`,
      [id]
    );

    // Fetch maintenance history for this asset
    const maintenanceResult = await db.query(
      `SELECT m.*, u.full_name AS technician_name
       FROM maintenance_logs m
       JOIN users u ON m.performed_by = u.id
       WHERE m.asset_id = $1
       ORDER BY m.started_at DESC
       LIMIT 10`,
      [id]
    );

    res.render('assets/detail', {
      title: `${asset.asset_code} - ${asset.name}`,
      asset,
      depreciation,
      loans: loansResult.rows,
      maintenanceLogs: maintenanceResult.rows
    });
  } catch (err) {
    console.error('Error fetching asset detail:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tải thông tin chi tiết tài sản.'
    });
  }
}

module.exports = {
  getAssets,
  getAssetDetail,
  calculateDepreciation
};