const db = require('../config/db');
const { logAssetStatusChange } = require('../utils/logger');

async function getMaintenanceList(req, res) {
  try {
    const ongoingSql = `
      SELECT m.*, a.asset_code, a.name AS asset_name, c.name AS category_name,
             u.full_name AS technician_name
      FROM maintenance_logs m
      JOIN assets a ON m.asset_id = a.id
      JOIN categories c ON a.category_id = c.id
      JOIN users u ON m.performed_by = u.id
      WHERE m.finished_at IS NULL
      ORDER BY m.started_at DESC
    `;

    const historySql = `
      SELECT m.*, a.asset_code, a.name AS asset_name, c.name AS category_name,
             u.full_name AS technician_name
      FROM maintenance_logs m
      JOIN assets a ON m.asset_id = a.id
      JOIN categories c ON a.category_id = c.id
      JOIN users u ON m.performed_by = u.id
      WHERE m.finished_at IS NOT NULL
      ORDER BY m.finished_at DESC
      LIMIT 20
    `;

    const [ongoingResult, historyResult] = await Promise.all([
      db.query(ongoingSql),
      db.query(historySql)
    ]);

    res.render('maintenance/index', {
      title: 'Quản lý bảo trì & sửa chữa thiết bị',
      ongoing: ongoingResult.rows,
      history: historyResult.rows
    });
  } catch (err) {
    console.error('Error fetching maintenance logs:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tải danh sách bảo trì.'
    });
  }
}

async function getCreateMaintenance(req, res) {
  try {
    // Only assets not borrowed and not retired can enter maintenance
    const assetsResult = await db.query(`
      SELECT a.*, c.name AS category_name
      FROM assets a
      JOIN categories c ON a.category_id = c.id
      WHERE a.status NOT IN ('borrowed', 'retired')
      ORDER BY a.name ASC
    `);

    res.render('maintenance/create', {
      title: 'Tạo phiếu bảo trì thiết bị',
      assets: assetsResult.rows,
      preselectedAssetId: req.query.asset_id || null,
      error: null
    });
  } catch (err) {
    console.error('Error loading maintenance form:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Không thể tải biểu mẫu bảo trì.'
    });
  }
}

async function postCreateMaintenance(req, res) {
  const { asset_id, type, description, estimated_cost } = req.body;
  const user = req.session.user;

  if (!asset_id || !type || !description) {
    return res.status(400).render('partials/error', {
      title: 'Dữ liệu không hợp lệ',
      statusCode: 400,
      message: 'Vui lòng chọn thiết bị, loại bảo trì và mô tả công việc!'
    });
  }

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    // Lock asset row
    const assetResult = await client.query(
      'SELECT id, asset_code, status FROM assets WHERE id = $1 FOR UPDATE',
      [asset_id]
    );
    const asset = assetResult.rows[0];

    if (!asset) {
      await client.query('ROLLBACK');
      return res.status(404).render('partials/error', {
        title: '404 Không tìm thấy',
        statusCode: 404,
        message: 'Thiết bị không tồn tại!'
      });
    }

    // Do NOT maintain borrowed or retired assets
    if (asset.status === 'borrowed') {
      await client.query('ROLLBACK');
      return res.status(400).render('partials/error', {
        title: 'Thiết bị đang được mượn',
        statusCode: 400,
        message: 'Không thể bảo trì tài sản đang được mượn! Vui lòng thu hồi trước khi bảo trì.'
      });
    }

    if (asset.status === 'retired') {
      await client.query('ROLLBACK');
      return res.status(400).render('partials/error', {
        title: 'Tài sản đã thanh lý',
        statusCode: 400,
        message: 'Không thể bảo trì tài sản đã thanh lý!'
      });
    }

    const prevStatus = asset.status;
    const cost = Math.max(0, parseInt(estimated_cost, 10) || 0);

    // Update asset status to maintenance if not already
    if (prevStatus !== 'maintenance') {
      await client.query(`UPDATE assets SET status = 'maintenance' WHERE id = $1`, [asset.id]);
      logAssetStatusChange(asset.asset_code, prevStatus, 'maintenance', user.username);
    }

    // Insert maintenance log
    await client.query(
      `INSERT INTO maintenance_logs (asset_id, type, description, cost, started_at, performed_by)
       VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP, $5)`,
      [asset.id, type, description.trim(), cost, user.id]
    );

    await client.query('COMMIT');
    res.redirect('/maintenance');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error creating maintenance:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Có lỗi xảy ra khi tạo bản ghi bảo trì.'
    });
  } finally {
    client.release();
  }
}

async function postFinishMaintenance(req, res) {
  const { id } = req.params;
  const { final_cost } = req.body;
  const user = req.session.user;

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    // Lock maintenance log
    const logResult = await client.query(
      `SELECT m.*, a.asset_code
       FROM maintenance_logs m
       JOIN assets a ON m.asset_id = a.id
       WHERE m.id = $1 FOR UPDATE`,
      [id]
    );
    const mLog = logResult.rows[0];

    if (!mLog || mLog.finished_at) {
      await client.query('ROLLBACK');
      return res.status(400).render('partials/error', {
        title: 'Không hợp lệ',
        statusCode: 400,
        message: 'Bản ghi bảo trì không tồn tại hoặc đã được hoàn tất trước đó!'
      });
    }

    const cost = Math.max(0, parseInt(final_cost, 10) || mLog.cost || 0);

    // Update maintenance log to finished
    await client.query(
      `UPDATE maintenance_logs
       SET finished_at = CURRENT_TIMESTAMP, cost = $1
       WHERE id = $2`,
      [cost, id]
    );

    // Check if asset has any other ongoing maintenance
    const otherOngoing = await client.query(
      `SELECT id FROM maintenance_logs WHERE asset_id = $1 AND finished_at IS NULL AND id != $2`,
      [mLog.asset_id, id]
    );

    // If no more ongoing maintenance, return asset to 'available'
    if (otherOngoing.rows.length === 0) {
      await client.query(`UPDATE assets SET status = 'available' WHERE id = $1`, [mLog.asset_id]);
      logAssetStatusChange(mLog.asset_code, 'maintenance', 'available', user.username);
    }

    await client.query('COMMIT');
    res.redirect('/maintenance');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error finishing maintenance:', err);
    res.status(500).render('partials/error', {
      title: 'Lỗi hệ thống',
      statusCode: 500,
      message: 'Có lỗi xảy ra khi hoàn tất bảo trì.'
    });
  } finally {
    client.release();
  }
}

module.exports = {
  getMaintenanceList,
  getCreateMaintenance,
  postCreateMaintenance,
  postFinishMaintenance
};